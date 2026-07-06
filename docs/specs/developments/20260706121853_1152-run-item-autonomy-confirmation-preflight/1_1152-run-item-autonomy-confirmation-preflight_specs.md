# Run Item Autonomy Confirmation Preflight - Spec

---

## Overview

Single-item workflow runs should give operators the same clear pre-mutation
policy summary that epic runs already provide. When a maintainer invokes
`/run-item` or `$run-item`, the command should explain the selected autonomy
policy, guardrail sources, checkpoint obligations, base branch, and copy-paste
equivalent before it starts tracker or branch mutations.

After the operator confirms that preflight, the run should continue through the
normal single-item workflow without repeatedly asking for the same authority at
each stage. The confirmation is scoped to the selected item and does not waive
new stop conditions, pending checkpoints, failed review, failed CI, or merge
risk violations.

## Brief Objective List

Derived from issue #1152:

1. Align `$run-item` and `/run-item` command surfaces with the `/run-epic`
   preflight and confirmation style.
2. Show effective guardrails and selected policy in operator-friendly language,
   not only raw prelude JSON.
3. Include explicit guidance for pending checkpoints: accept, satisfy, waive
   with rationale, or provide a checkpoint policy file.
4. Treat confirmation as invocation-scoped authority for the selected single
   item.
5. Preserve the existing guardrails enforcement path for risk classification,
   delegated gate, audit records, PR readiness checks, CI checks, and named stop
   conditions.
6. Keep Codex, Claude, and Cursor command surfaces aligned when command docs or
   wrappers change.
7. Ensure a confirmed run can continue through spec, plan, implementation,
   reviewer loops, CI loops, and delegated merge gates according to selected
   policy without redundant approval prompts.
8. Document how to run a single item with explicit autonomy flags.
9. Cover inferred policy, explicit policy, pending checkpoints, and
   no-redundant-prompt continuation with tests or smoke coverage.

## Use Cases

### Use Case 1: Operator reviews a single-item policy before mutation

**Actor**: Template maintainer or workflow operator.
**Preconditions**: A non-epic tracker item exists and the operator invokes
`/run-item` or `$run-item` for exactly one target.

**Steps**:

1. The command resolves the item, base branch, guardrails, selected policy, and
   checkpoint policy without mutating repository or tracker state.
2. The command prints a concise confirmation summary in plain operator
   language.
3. The operator confirms, customizes the requested authority, or re-invokes with
   corrected flags.

**Postconditions**: No mutation happens until the operator has confirmed the
selected invocation-scoped policy or supplied explicit autonomy flags.

**Information shown**:

- Resolved item identifier, title, status, type, and base branch.
- Effective autonomy mode and selected values for delegated review, backlog
  start authority, merge authority, and risk ceiling.
- Field sources for each selected value.
- Pending checkpoints and the required human action for each one.
- A copy-paste command that reproduces the selected policy.
- A read-only guarantee stating that no tracker, branch, PR, label, comment,
  merge, issue closure, or cleanup mutation has happened yet.

**Actions available**:

- Confirm the selected policy.
- Re-invoke with explicit autonomy flags.
- Provide or reference a checkpoint policy file.
- Stop the run before mutation.

**Considerations**:

- The preflight should be understandable without requiring the operator to
  inspect raw JSON.
- Confirmation must be scoped to the selected single item and should not become
  blanket authority for unrelated work.

### Use Case 2: Confirmed run continues without redundant approval prompts

**Actor**: Template maintainer or workflow operator.
**Preconditions**: The operator has confirmed the preflight for one item or
provided all required autonomy flags explicitly.

**Steps**:

1. The workflow runner starts or resumes the selected item according to its
   current tracker status.
2. The runner advances through spec, plan, implementation, review, and CI stages
   according to the selected policy and configured guardrails.
3. At normal handoff points, the runner uses the invocation-scoped confirmation
   instead of asking again for the same pre-approved action.
4. If a new stop condition appears, the runner stops and names the specific
   reason.

**Postconditions**: The item advances until it reaches a real terminal
condition: a human review or merge handoff, a delegated merge result, an
unresolved checkpoint, failed review or CI, a risk violation, or another named
stop condition.

**Information shown**:

- Current stage and next deterministic action.
- Whether the current action is covered by the confirmed policy.
- Any new stop condition that requires human input.
- Final tracker, branch, PR, review, CI, and audit state for the stage.

**Actions available**:

- Continue the run under the confirmed policy.
- Address review or CI findings and rerun the relevant loop.
- Stop at human review, merge, checkpoint, or risk gates.

**Considerations**:

- The feature should remove repeated approval prompts for the same confirmed
  policy, not remove meaningful guardrail stops.
- Pending checkpoints still require satisfaction or waiver at the appropriate
  point.

### Use Case 3: Operator supplies explicit autonomy flags

**Actor**: Template maintainer or workflow operator.
**Preconditions**: The operator knows the authority they want to grant for a
single-item run.

**Steps**:

1. The operator invokes `/run-item` with explicit flags such as
   `--delegate-review`, `--may-merge`, `--may-start-backlog true`, and
   `--max-risk medium`.
2. The command resolves and prints the policy summary.
3. Because all required autonomy flags were explicit, the command proceeds
   after printing the summary unless scope ambiguity, unresolved checkpoints, or
   guardrail conflicts still require a stop.

**Postconditions**: Explicit operator intent is honored without an avoidable
second confirmation prompt.

**Information shown**:

- The explicit values selected by the operator.
- Any value narrowed by repository guardrails or selected mode.
- Any checkpoint or stop condition that still blocks mutation or merge.

**Actions available**:

- Proceed under the explicit policy.
- Re-invoke with narrower or broader authority.
- Provide checkpoint policy input when required.

**Considerations**:

- Explicit flags should not grant authority that the effective autonomy mode or
  repository guardrails forbid.
- The summary still prints before mutation so the operator can verify the
  resolved result.

### Use Case 4: Maintainer keeps agent command surfaces aligned

**Actor**: Template maintainer.
**Preconditions**: The run-item preflight behavior or command instructions are
changed.

**Steps**:

1. The maintainer updates the canonical workflow protocol or helper behavior.
2. The maintainer updates matching Codex, Claude, and Cursor command surfaces.
3. The maintainer verifies that docs and wrappers describe the same confirmation
   semantics.

**Postconditions**: Operators see consistent run-item behavior regardless of
which supported agent surface they use.

**Information shown**:

- Which command surfaces support the preflight.
- How each surface handles explicit flags, inferred policy, checkpoints, and
  confirmation.

**Actions available**:

- Invoke `/run-item` or `$run-item` from supported surfaces.
- Follow the same copy-paste command guidance across agent adapters.

**Considerations**:

- Wrapper text should stay thin and point back to the canonical workflow
  behavior instead of creating separate policy models.

## Business Rules

- `/run-item` and `$run-item` must run the shared bounded prelude before any
  tracker, branch, PR, label, comment, merge, issue-close, or cleanup mutation.
- The preflight summary must be printed for every direct single-item run,
  including runs where all autonomy flags were explicit.
- If any required autonomy value is inferred, scope is ambiguous, or pending
  checkpoints remain, the command must stop before mutation until the operator
  confirms, customizes, or supplies checkpoint policy input.
- If all required autonomy flags are explicit and no unresolved checkpoint or
  guardrail conflict requires a stop, those flags serve as confirmation after
  the summary is printed.
- Confirmation applies only to the resolved single item and the selected
  invocation-scoped policy.
- Confirmation must not waive new or later guardrail stops, failed CI,
  unresolved blocking review, missing permissions, destructive-action stops,
  missing audit evidence, or risk violations.
- Pending checkpoints must either be satisfied or waived with rationale before
  the stage they guard can proceed beyond its checkpoint.
- Effective guardrails, field sources, and checkpoint policy must be explained
  in operator-facing language.
- The copy-paste command must reproduce the selected policy as closely as the
  command surface supports.
- The run-item implementation must reuse the existing bounded prelude and
  guardrails policy path rather than introducing a second autonomy model.
- Codex, Claude, and Cursor command surfaces must remain behaviorally aligned
  when this operator contract changes.

## Operational Visibility

- **Preflight summary**: Operators can see the resolved item, base branch,
  selected policy, field sources, checkpoint policy, copy-paste command, and
  read-only guarantee before mutation.
- **Confirmation record**: The run output makes clear whether the operator
  confirmed inferred policy or supplied explicit flags.
- **Continuation behavior**: Stage handoffs show when the confirmed policy
  covers continued execution and when a new stop condition interrupts it.
- **Checkpoint handling**: Pending, satisfied, and waived checkpoints are
  visible in the run output and any required audit evidence.
- **Audit trail**: Existing PR disposition and work-item ledger records remain
  the source of truth for delegated review and merge decisions.
- **Surface parity**: Command docs and wrappers tell operators the same
  confirmation story across Codex, Claude, and Cursor.

## Acceptance Criteria

- [ ] `/run-item <item>` and `$run-item <item>` print a concise policy
      confirmation summary before mutation.
- [ ] The summary includes the resolved item, effective policy, field sources,
      checkpoint policy, base branch, copy-paste equivalent, and read-only
      guarantee.
- [ ] Inferred policy, ambiguous scope, or pending checkpoints stop before
      mutation until the operator confirms, customizes, or supplies checkpoint
      policy input.
- [ ] Runs invoked with all required autonomy flags explicitly provided print
      the summary and then proceed without an avoidable second confirmation
      prompt when no checkpoint or guardrail conflict blocks them.
- [ ] A confirmed single-item run does not ask again for the same
      invocation-scoped authority at normal spec, plan, implementation,
      reviewer-loop, CI-loop, or delegated-gate handoffs.
- [ ] New guardrail stops, unresolved checkpoints, blocking review findings,
      failing CI, missing permissions, destructive actions, and risk violations
      still stop the run with a named reason.
- [ ] Pending checkpoints cannot be silently waived; any waiver requires an
      explicit rationale or checkpoint policy input.
- [ ] The implementation reuses the shared bounded prelude and existing
      guardrails enforcement path.
- [ ] Documentation explains explicit single-item autonomy flags, including
      delegated review, merge authority, backlog-start authority, and max risk.
- [ ] Codex, Claude, and Cursor command surfaces describe the same run-item
      confirmation behavior.
- [ ] Tests or smoke coverage verify inferred policy, explicit policy, pending
      checkpoints, and confirmed continuation without redundant prompts.

## Coverage Matrix

| Brief objective | Covered by |
| --- | --- |
| 1. Align command surfaces with `/run-epic` preflight style | AC1, AC2, AC10; Use Cases 1 and 4 |
| 2. Show guardrails and selected policy in operator language | AC2; Business Rules; Operational Visibility |
| 3. Include checkpoint guidance | AC2, AC3, AC6, AC7; Use Cases 1 and 2 |
| 4. Treat confirmation as invocation-scoped authority | AC5; Business Rules; Use Case 2 |
| 5. Preserve guardrails enforcement path | AC6, AC8; Business Rules |
| 6. Keep Codex, Claude, and Cursor aligned | AC10; Use Case 4 |
| 7. Continue confirmed runs without redundant prompts | AC4, AC5; Use Cases 2 and 3 |
| 8. Document explicit autonomy flags | AC9; Use Case 3 |
| 9. Cover key policy paths with tests or smoke coverage | AC11 |

## Out of Scope (MVP)

- Changing the underlying guardrails schema or adding new autonomy modes.
- Granting automatic merge authority beyond what effective guardrails permit.
- Replacing the existing delegated gate, risk classifier, reviewer loop, CI
  loop, or audit-trail helpers.
- Changing `/run-epic` confirmation behavior except where shared documentation
  must stay consistent.
- Adding a new tracker workflow stage for preflight confirmation.
