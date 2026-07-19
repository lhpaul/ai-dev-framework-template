# Deprecate Direct Item-Orchestrator Command for Cursor Runs - Spec

---

## Overview

Cursor users need `/run-item` to be the single, obvious way to advance one
workflow item while still receiving the model-routing benefits of configured
Cursor subagents. The workflow should hide or clearly deprecate direct
`/item-orchestrator` invocation as a user-facing path, because that command
creates two competing entrypoints for the same single-item workflow.

The expected user experience is that `/run-item` remains the canonical command
across Cursor, Claude, and Codex. In Cursor, the command preserves the bounded
prelude and then routes internally through configured orchestration and stage
agents when the runner supports that handoff, so stage work uses the intended
model assignments instead of defaulting to inline Composer execution.

## Brief Objective List

Derived from issue #1190:

1. Keep `/run-item` as the canonical single-item command across Cursor, Claude,
   and Codex surfaces.
2. Make Cursor `/run-item` use configured subagent handoff internally when
   Cursor supports it.
3. Preserve configured stage-specific model routing for orchestration, product,
   planning, implementation, and code-review work.
4. Deprecate or hide direct user invocation of `/item-orchestrator` where
   possible.
5. Remove guidance that tells Cursor users to invoke `/item-orchestrator` as the
   normal path.
6. Preserve the bounded prelude contract and avoid duplicated scope or policy
   prompts during internal handoff.
7. Align mirrored workflow surfaces that mention direct invocation or fallback
   behavior.
8. Add or update workflow smoke-test or documentation coverage for the canonical
   Cursor path and model-routing intent.

## Use Cases

### Use Case 1: Cursor operator starts one workflow item

**Actor**: Cursor operator.
**Preconditions**: The operator has a single non-epic workflow item to advance
and Cursor workflow commands are available.

**Steps**:

1. The operator invokes `/run-item <target>`.
2. The command presents the bounded prelude summary before any mutation.
3. After explicit policy flags or human confirmation, the command continues the
   item through the configured single-item workflow.
4. When Cursor supports internal handoff, the workflow routes orchestration and
   stage work through configured Cursor subagents.

**Postconditions**: The item advances through the canonical single-item workflow
without the operator needing to invoke `/item-orchestrator` directly.

**Information shown**:

- Resolved item, base branch, selected policy, checkpoint guidance, and
  read-only prelude guarantee.
- The terminal state of the item: waiting on human review, blocked, escalated,
  or completed by delegated merge when authorized.

**Actions available**:

- Confirm, customize, or rerun the policy before mutation.
- Continue normal workflow review or merge actions after the item reaches its
  terminal state.

**Considerations**:

- The user-facing entrypoint should remain `/run-item` even when the actual
  Cursor execution uses an internal orchestration subagent.
- If Cursor cannot perform the internal handoff in a given environment, the
  workflow must still remain scoped to `/run-item` and clearly document the
  fallback behavior.

### Use Case 2: Cursor workflow routes stage work to configured models

**Actor**: Cursor operator and configured workflow subagents.
**Preconditions**: The item has reached a stage that needs product, planning,
implementation, review, or orchestration work.

**Steps**:

1. The single-item workflow identifies the next deterministic stage.
2. The workflow uses the configured Cursor agent for that stage when supported.
3. The stage agent runs with the model assignment declared for that role.
4. The item returns to the single-item control loop for review, CI, tracker, and
   terminal-state handling.

**Postconditions**: Expensive or high-reasoning models are reserved for stages
that need them, while orchestration and mechanical stages can use their
configured models.

**Information shown**:

- Which workflow stage is being advanced.
- Which user-facing command initiated the run.
- Whether the run is using configured subagent handoff or documented fallback
  behavior.

**Actions available**:

- Continue the current workflow stage.
- Stop for a human decision when requirements, guardrails, review, CI, or
  permissions require it.

**Considerations**:

- Model-routing guidance should be framed as workflow behavior, not as a reason
  for users to bypass `/run-item`.
- Stage handoff must not widen scope beyond the selected item.

### Use Case 3: User discovers deprecated direct item-orchestrator path

**Actor**: Cursor operator reading commands, agents, or workflow docs.
**Preconditions**: The operator finds a direct `/item-orchestrator` reference or
attempts to invoke it manually.

**Steps**:

1. The operator sees clear guidance that direct `/item-orchestrator` invocation
   is deprecated or not the normal user-facing path.
2. The guidance points the operator back to `/run-item <target>`.
3. If the direct path remains present for internal compatibility, it explains
   that it exists for handoff or legacy compatibility rather than normal use.

**Postconditions**: The operator understands that `/run-item` is the canonical
entrypoint and does not have to choose between two equivalent-looking commands.

**Information shown**:

- Deprecation or internal-use wording for direct item-orchestrator invocation.
- The replacement command to use.
- Any relevant compatibility note for existing automation.

**Actions available**:

- Invoke `/run-item <target>`.
- Update local workflow habits or documentation references.

**Considerations**:

- Existing internal handoff surfaces may still need to mention
  `item-orchestrator`; those mentions should distinguish internal execution
  from user-facing invocation.

### Use Case 4: Maintainer verifies mirrored workflow guidance

**Actor**: Template maintainer.
**Preconditions**: The workflow ships mirrored guidance for Cursor, Claude,
Codex, and shared repository docs.

**Steps**:

1. The maintainer reviews command, agent, skill, and shared documentation
   surfaces that mention `/run-item` or `item-orchestrator`.
2. The maintainer verifies that Cursor-facing guidance presents `/run-item` as
   canonical.
3. The maintainer verifies that mirrored non-Cursor surfaces remain accurate and
   do not overpromise Cursor-specific handoff behavior.
4. The maintainer runs documentation or smoke-test coverage that captures the
   expected command path and model-routing intent.

**Postconditions**: The workflow surfaces are aligned and future template syncs
are less likely to reintroduce direct invocation guidance.

**Information shown**:

- The list of updated workflow surfaces.
- The smoke-test or documentation coverage that verifies the desired behavior.
- Any intentionally retained internal or compatibility references.

**Actions available**:

- Accept the updated workflow guidance.
- Request changes if a surface still presents `/item-orchestrator` as the normal
  Cursor path.

## Business Rules

- `/run-item` must be the canonical single-item command for Cursor, Claude, and
  Codex user-facing guidance.
- Cursor-facing guidance must not tell users to invoke `/item-orchestrator` as
  the normal path for single-item workflow execution.
- Direct `item-orchestrator` references that remain for internal handoff or
  compatibility must be clearly distinguished from user-facing invocation.
- Cursor `/run-item` must preserve the bounded prelude before mutation.
- Internal handoff after `/run-item` confirmation must not rerun the bounded
  prelude or re-prompt for the same confirmed scope and selected policy.
- Stage-specific work should use configured Cursor subagents and their assigned
  models when the runner supports that handoff.
- If a runner cannot perform a supported internal handoff, the documented
  fallback must keep `/run-item` as the initiating command and must preserve
  scope, policy, guardrail, review, and CI stops.
- Mirrored workflow surfaces must remain consistent about canonical entrypoints,
  deprecated aliases, and internal handoff behavior.

## Operational Visibility

- **Documentation visibility**: Workflow command, agent, skill, and AGENTS
  guidance should clearly identify `/run-item` as the user-facing entrypoint and
  label direct `item-orchestrator` usage as internal or deprecated where
  applicable.
- **Review visibility**: The spec PR and later implementation PR should make any
  intentionally retained direct `item-orchestrator` references easy for
  reviewers to distinguish from normal user-facing guidance.
- **Smoke-test visibility**: Workflow smoke-test coverage should include checks
  for canonical Cursor `/run-item` guidance and for model-routing intent through
  configured subagent handoff.

## Acceptance Criteria

- [ ] Cursor command guidance presents `/run-item <target>` as the canonical
      single-item entrypoint.
- [ ] Cursor-facing docs no longer instruct users to directly invoke
      `/item-orchestrator` as the normal workflow path.
- [ ] Any remaining direct `item-orchestrator` references are marked as internal
      handoff, legacy compatibility, or deprecated user-facing usage.
- [ ] Cursor `/run-item` behavior is specified to run the bounded prelude first,
      then hand off internally with confirmed scope and policy when supported.
- [ ] The handoff contract says the receiving orchestration context must not
      duplicate the bounded prelude or re-prompt for the same confirmed policy.
- [ ] Stage-specific handoff guidance covers configured Cursor agents for
      product, plan, implementation, and review stages.
- [ ] Mirrored workflow surfaces that mention `/run-item`,
      `/run-item-work`, or `item-orchestrator` remain aligned after the change.
- [ ] Smoke-test or documentation coverage verifies that Cursor's canonical path
      is `/run-item` and that configured model routing remains part of the
      workflow intent.

## Coverage Matrix

| Brief objective | Coverage |
| --- | --- |
| 1. Keep `/run-item` canonical across Cursor, Claude, and Codex | AC1, AC7 |
| 2. Make Cursor `/run-item` use configured subagent handoff internally | AC4, AC5, AC6 |
| 3. Preserve stage-specific model routing | AC6, AC8 |
| 4. Deprecate or hide direct `/item-orchestrator` invocation | AC2, AC3 |
| 5. Remove normal-path `/item-orchestrator` guidance | AC2, AC3, AC7 |
| 6. Preserve bounded prelude without duplicate prompts | AC4, AC5 |
| 7. Align mirrored workflow surfaces | AC7 |
| 8. Add or update workflow smoke-test/documentation coverage | AC8 |

## Out of Scope (MVP)

- Changing the actual model assignments of Cursor agents.
- Removing internal agent files that Cursor needs for subagent execution.
- Changing Claude or Codex runtime behavior beyond keeping mirrored guidance
  consistent with the canonical `/run-item` entrypoint.
- Implementing a new tracker state, branch type, or workflow stage.
- Changing `/run-items`, `/run-work`, or `/run-epic` behavior except for
  references needed to keep command guidance consistent.
