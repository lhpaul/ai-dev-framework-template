# Stage-Role Permission Denial Recovery — Spec

## Overview

A workflow item may successfully delegate work to a stage role and still have that role's specific tool or local-path action denied. Today the documented fallback for a denied Work Item Runner applies to a different orchestration boundary, while stage-role denial lacks an outcome. This feature gives operators a clear stop and recovery path without turning denied implementation or review into silent inline work by the orchestrator.

## Brief Objective List

- **BO-1**: Define the item-orchestrator outcome when a reachable, dispatched stage role reports a tool or path permission denial.
- **BO-2**: Preserve dispatch-profile restrictions and review independence; do not silently absorb denied product work inline.
- **BO-3**: Explicitly scope the existing portfolio fallback to the Portfolio Orchestrator–Work Item Runner boundary.
- **BO-4**: Make the item-level denial contract point to the stage-role mechanism rather than treating the portfolio fallback as its recovery.
- **BO-5**: Decide whether harness tool or local-path denial has a named stop distinct from missing credentials or GitHub permissions.

## Use Cases

### Use Case 1: Dispatched stage role encounters a denial

**Actor**: A reachable stage role, such as a spec writer, planner, implementer, or reviewer, carrying out work delegated by an item orchestrator.

**Preconditions**: The role received its assignment and the execution environment explicitly denies a tool action or access to a local path. The failure is not merely an unavailable role or a missing credential, GitHub permission, or access token.

**Steps**:

1. The stage role stops the denied action, reports the denial and its known target to the item orchestrator, and preserves the work already present.
2. The item orchestrator stops the affected item before dependent mutations or a completion claim. It reports the named stop, affected item and stage, denied tool or path when known, and a concrete action the operator can take.
3. The operator resolves the denied access or explicitly selects another authorized context in which the same stage role can perform its assigned action. Before resuming, the runner checks durable state and reconciles any action whose outcome was uncertain. A changed context starts a fresh bounded run and declares the applicable dispatch profile again; a same-context resume retains the current profile and rechecks all applicable gates. This context-change rule applies to the new tool/path-denial recovery; the existing credential-denial route retains its own profile rules.
4. After the operator confirms an access or environment correction, the same owning stage role resumes the appropriate work under the existing isolation, review, and workflow gates. A single resumed attempt may verify that access now works; a renewed denial stops again and requires a new correction rather than an automatic retry loop.

**Postconditions**: The work resumes only after the denial is resolved and the assigned role can perform the action, or remains stopped with an actionable report. Neither an attempted action nor an incomplete role report is treated as a completed stage.

**Information shown**: The item, stage, known denied action or target, work state, named stop, and unblock action.

**Actions available**: The operator can correct access or select an authorized context for the same stage role, or leave the item stopped.

**Considerations**: The denied operation might have produced partial local work or have an uncertain remote outcome. Preserve it for inspection; never assert that nothing was changed without evidence. Do not repeat a possibly successful remote mutation until its actual state is established.

### Use Case 2: Operator chooses not to restore access

**Actor**: The operator supervising the bounded run.

**Preconditions**: The stage-role denial cannot be remedied in the current context or the operator decides not to proceed.

**Steps**: The operator reviews the stop report and chooses not to restore access.

**Postconditions**: The item remains stopped and the report identifies the unresolved action. Other independently eligible items may continue only under their existing isolation and supervision rules; items depending on the stopped item or its incomplete PR remain held. No stopped item's denied action is executed indirectly as a workaround.

**Information shown**: The unresolved blocker and known state of the stopped item.

**Actions available**: Leave the item stopped or later correct access and resume under the first use case.

**Considerations**: Preserve existing work and hold dependent items.

## Business Rules

1. A reached role's tool or local-path permission denial is an infrastructure/access failure, not a finding that the work product needs changes. Do not apply `needs-fixes` solely for this failure.
2. The named stop condition for this case is `stage_role_tool_or_path_denied`. It is distinct from `missing_required_secret_or_permission` for a missing credential, GitHub permission, or access token, and from `dispatch_handoff_unavailable` for a role that cannot be reached. A denial of a reachable role is not itself evidence that dispatch failed.
3. The same stop applies to a single denied tool call or a broader denied capability, and to any stage role. The report describes the actual known denial; it must not invent a path or claim a denial when the outcome is unknown. If a report establishes an access refusal but its cause cannot be distinguished, or a denied action has an uncertain outcome, stop as `unclear_requirements`, identify the affected item and stage and the missing facts, and ask the operator to resolve them rather than misclassifying the cause. The guardrail definition of `unclear_requirements` must explicitly include these denial-related uncertainty cases while preserving its existing uses. A generic tool failure without evidence of an access refusal remains under its existing error contract and is not automatically classified as this case.
4. If a report contains both an independently established credential denial and an independently established tool or path denial, report both applicable stops and remedies. An unknown cause is not promoted to a confirmed second cause. Resolve all applicable blocking causes before the affected action resumes.
5. The orchestrator must not evade the denial through another tool, identity, or path, or through inline authorship or review. An operator may explicitly choose a genuinely authorized context for the same role; this is access correction, not an agent-selected workaround. The same stage role remains accountable after an authorized environment or permission correction; reviewer independence and all existing gates remain in force. Merely rewording a denied action or repeatedly dispatching without an operator-confirmed access or environment correction is not recovery. The same rule covers a denied merge or other action that the run assigned to a stage role: the parent cannot replay that denied operation inline as a workaround. Once the operator corrects access, the originally assigned stage role resumes the action, subject to the existing workflow gates and merge authority; a denial does not itself transfer ownership to the parent.
6. This contract covers stage-role denial at the item-orchestrator boundary across execution environments and dispatch profiles. Existing stricter profile rules still apply; in particular, a parent-orchestrated context does not implement or review product work inline. When a read-only or unavailable-handoff stop also applies, report every independently established applicable stop and satisfy all its conditions; the stricter no-mutation outcome governs until all blocking conditions are resolved.
7. The Portfolio Orchestrator's existing Work Item Runner denial handling remains scoped to that boundary. A stage-role denial must not be relabeled as a Work Item Runner denial or automatically routed to its inline fallback. If a Work Item Runner reports a separate denial of its own action, its existing contract remains applicable to that separate failure.
8. Reports contain the exact stop name, affected item and stage, the known denied action or target, the work state known to the runner, and the operator action needed to unblock. Do not expose credentials or private configuration. A denial must not be converted into an approval, clean review, merged state, or completed tracker stage.

## Decision and Recovery Matrix

| Situation | Outcome | Next action |
| --- | --- | --- |
| Reachable stage role explicitly reports harness tool or local-path access denied | Stop affected item: `stage_role_tool_or_path_denied` | Operator fixes access or chooses an authorized context for the same role; reconcile uncertain work. A changed context requires a fresh run and profile declaration |
| Reachable role reports missing credential, GitHub permission, or access token only | Existing `missing_required_secret_or_permission` stop | Use its existing credential or permission remedy and preserve role ownership |
| Both causes independently established | Both relevant stops | Resolve both before the affected action resumes |
| A separately established read-only or handoff stop also applies | Report both applicable stops; no mutation | Resolve all blocking conditions and re-evaluate the active profile |
| Role cannot be reached | Existing handoff-unavailable behavior for the applicable profile | Follow the existing dispatch-profile stop and recovery rules |
| An established access refusal has an unknown cause, or a denied action has an uncertain outcome | Stop as `unclear_requirements`, without a false diagnosis or completion | Name the item and stage, inspect durable state, and obtain the missing facts before retry |
| Generic tool error without evidence of access refusal | Existing tool-error behavior | Do not classify as a permission denial without evidence |
| Work Item Runner itself is denied at the portfolio boundary | Existing Protocol 90 boundary-specific handling | Follow that contract and its isolation requirements, without treating it as stage-role recovery |
| Access corrected, role available, uncertain state reconciled | Resume same stage role | Same context retains its profile and rechecks gates; a changed context starts a fresh run and declares its profile. A renewed denial stops again |
| Access remains denied or operator declines recovery | Item stays stopped | Report blocker; continue unrelated eligible work only where existing rules permit |

The `/run-item`, `/run-items`, and `/run-epic` command guidance and the portfolio, item, epic, and stage-role guidance must point to the same outcome. The read-only `/run-work` scan does not dispatch stage work or use this recovery path; its existing profile and read-only rules remain in force. The existing no-named-stop and no-recovery statements for #1746 in Protocols 90, 91, and 95, guardrail enforcement, and Cursor dispatch-profile guidance are superseded for this stage-role case; the #1462 specification remains a historical record of its scope. Examples must not imply that a stopped stage role was unreachable or that denied product work was completed inline.

## Statuses / Enum Values

| Stop condition | Display label | Meaning |
| --- | --- | --- |
| `stage_role_tool_or_path_denied` | Stage-role tool or path denied | A reachable role reports an explicit harness tool or local-path denial; the affected item stops until access is corrected. |

This stop is cleared only after the operator confirms an access or context correction and the owning role resumes under the applicable gates. A repeated denial stops again. Other named stops retain their existing definitions except the explicitly bounded `unclear_requirements` extension above.

## Operational Visibility

The role's denial report and the item's terminal report let the operator distinguish a tool or path denial from credential and handoff failures. The item report records the stop and known work state without printing secrets. Record a resumable stop report in the existing work-item or PR record when that write is permitted, including item, stage, role, denied action, known state, and unblock action. If no such write is available, return those details to the operator as a handoff and do not claim durable recording. Where a PR or durable work already exists, retain its identity and review state for safe resumption; do not overwrite a successful prior stage or invent a new failure label.

## Acceptance Criteria

- [ ] A reachable dispatched stage role reporting a harness tool or local-path denial stops the affected item with `stage_role_tool_or_path_denied`, naming the item, stage, known denied action or target, and a concrete unblocking action.
- [ ] The outcome applies to implementation, specification, planning, and review roles without allowing the orchestrator to silently author or review the denied work. Reviewer independence and each dispatch profile's stricter rules remain intact.
- [ ] Once access is corrected or a suitable context is provided, the same owning role can resume after the runner verifies any uncertain prior mutation; a repeated denial stops again without an automatic retry loop.
- [ ] Missing credentials or GitHub access and an unreachable stage role follow their existing distinct contracts; simultaneous established causes and independently applicable read-only or handoff stops are reported separately, and an unknown cause stops as `unclear_requirements` without false classification.
- [ ] Protocol 90's existing permission-denial fallback is explicitly scoped to the Portfolio Orchestrator–Work Item Runner boundary, and Protocol 91's stage-role denial guidance points to the stage-role mechanism.
- [ ] A denial alone does not add `needs-fixes`, mark the stage complete, approve a review, or claim that a possibly partial or uncertain action did not occur; dependent items remain held.
- [ ] The command, Protocol 90, 91 and 95, dispatch-profile, guardrail, and role surfaces replace their current no-recovery guidance and agree on the stop, ownership, recovery, and no-bypass behavior; each applicable path can be exercised with fabricated denial reports without real credential changes.

## Out of Scope (MVP)

- Changing the Portfolio Orchestrator–Work Item Runner fallback or the definition of credential and unreachable-handoff stops.
- Granting permissions, altering harness policy, or providing a way to bypass a denied action.
- Treating normal test failures, content-review findings, or generic tool errors as permission denials without evidence.
- Requiring automatic retries, changing a stage role's authority, or making an external execution environment support delegation.
- Resolving the separately tracked batch-context enforcement issue #1745.
