# Block Implementation Code in Plan PRs - Spec

---

## Overview

Workflow operators need plan-stage and spec-stage PRs to stay aligned with the
stage they represent. When an implementation-plan PR contains application code,
migrations, UI files, or other implementation artifacts, the workflow must make
that mismatch visible and must not automatically mark the PR ready for human
review as if it were a normal plan document.

This feature adds a product workflow requirement for stage-alignment checks on
documentation-stage PRs. The implementation plan will decide the exact technical
gate shape, but the user-facing outcome is clear: a collapsed plan-plus-code PR
is flagged before readiness handoff, includes enough evidence for a reviewer to
understand what was found, and waits for human or workflow correction instead of
silently proceeding.

## Brief Objective List

Derived from issue #1206:

1. Detect when a plan-stage PR contains files outside the expected plan/spec
   documentation scope.
2. Prevent automatic `ready-for-human-review` handoff when a plan-stage PR has
   implementation files.
3. Notify reviewers and the item runner with a clear warning that names the
   stage mismatch and lists the unexpected files.
4. Cover spec-stage PRs with the same stage-alignment expectation where
   applicable, so documentation-stage PRs cannot carry implementation work.
5. Allow the implementation plan to choose the enforcement mechanism, including
   protocol-level gating, CI enforcement, or a combination.
6. Protect restarted or resumed agent runs from inheriting a contaminated plan
   branch and advancing it without inspection.

## Use Cases

### Use Case 1: Item runner prepares a plan PR for handoff

**Actor**: Work Item Runner.
**Preconditions**: A workflow item is in the plan stage and has an
implementation-plan PR ready to evaluate before human handoff.

**Steps**:

1. The runner reaches the readiness path for the plan PR.
2. Before applying human-review readiness, the workflow checks whether the PR's
   changed files match the documentation-stage expectation.
3. If the PR contains only plan/spec documentation artifacts, the workflow
   continues through the normal review, CI, label, and tracker path.
4. If the PR contains implementation artifacts, the workflow stops automatic
   readiness handoff and records the mismatch.

**Postconditions**: A plan PR with implementation artifacts is not silently
marked ready for human review.

**Information shown**:

- The PR branch stage being evaluated.
- Whether the PR is stage-aligned or stage-mismatched.
- The unexpected files that caused the mismatch.
- The expected next action: split the work into the correct stage, escalate for
  human decision, or use an explicit documented override if one exists.

**Actions available**:

- Continue normal readiness when the PR is stage-aligned.
- Stop and request correction or human review when the PR is stage-mismatched.
- Re-run the check after the PR diff changes.

**Considerations**:

- The check must run before readiness labels are applied, not only after a human
  notices the PR content.
- The warning should be actionable without requiring the reviewer to inspect the
  entire diff manually.

### Use Case 2: Human reviewer sees a stage-collapse warning

**Actor**: Human reviewer or maintainer.
**Preconditions**: A documentation-stage PR contains implementation artifacts and
the workflow has detected the mismatch.

**Steps**:

1. The reviewer opens the PR and sees a warning produced by the workflow.
2. The warning explains that the PR branch represents a plan/spec stage but the
   diff includes implementation artifacts.
3. The warning lists the unexpected file paths or an equivalent concise
   evidence summary.
4. The reviewer decides whether the PR should be corrected, split, explicitly
   accepted as an exception, or escalated for workflow repair.

**Postconditions**: The reviewer receives an explicit stage-collapse signal
before treating the PR as a normal plan or spec artifact.

**Information shown**:

- The expected artifact type for the PR stage.
- The unexpected artifact list.
- The consequence: automatic readiness handoff is blocked until corrected or
  explicitly resolved.

**Actions available**:

- Ask the agent to move implementation work to the implementation stage.
- Approve an exception through the workflow mechanism chosen in the
  implementation plan.
- Request changes on the PR.

**Considerations**:

- The warning must not be phrased as a code-quality review finding. The problem
  is stage collapse: code may be correct while still being in the wrong workflow
  stage.

### Use Case 3: Restarted agent resumes a contaminated branch

**Actor**: Work Item Runner resuming a partial item.
**Preconditions**: A previous agent session wrote implementation files on a
plan or spec branch, and a later run resumes from that branch or PR.

**Steps**:

1. The runner resolves the existing branch or PR as part of normal resume
   behavior.
2. The runner evaluates the PR diff against the branch stage before human-ready
   handoff.
3. The runner detects implementation artifacts that do not belong to the
   documentation stage.
4. The runner records the mismatch and stops the automatic ready path.

**Postconditions**: Restarted work cannot inherit an already-contaminated plan
or spec branch and advance it as if the stage artifact were valid.

**Information shown**:

- That the mismatch was found during resume.
- The stage and unexpected files involved.
- Whether the next action is correction, split, or human decision.

**Actions available**:

- Correct the branch before re-running readiness.
- Escalate to the human when preserving the combined PR is intentional.

### Use Case 4: Template maintainer verifies documentation-stage alignment

**Actor**: Template maintainer.
**Preconditions**: The workflow has been updated to include a stage-alignment
requirement for documentation-stage PRs.

**Steps**:

1. The maintainer reviews the workflow behavior for plan and spec PR readiness.
2. The maintainer verifies that plan/spec PRs with implementation artifacts are
   detected before `ready-for-human-review`.
3. The maintainer verifies that valid documentation-stage PRs continue through
   the normal review and CI path.
4. The maintainer verifies that tests or documented smoke evidence cover both
   aligned and mismatched examples.

**Postconditions**: The template provides a reusable stage-alignment guarantee
for downstream projects using the workflow.

**Information shown**:

- The covered PR stages.
- The expected documentation-stage artifact boundary.
- The verification evidence used to prove the guard works.

**Actions available**:

- Accept the workflow update.
- Request additional coverage if a documentation-stage PR can still bypass the
  guard.

## Business Rules

- Documentation-stage PRs must be checked for stage alignment before automatic
  human-review readiness is applied.
- Documentation-stage PRs include spec branches and implementation-plan
  branches.
- A documentation-stage PR with implementation artifacts must not receive
  automatic `ready-for-human-review` handoff until the mismatch is corrected,
  explicitly resolved, or escalated according to the implementation plan's
  chosen workflow.
- The warning must identify both the expected stage artifact and the unexpected
  files or file categories found.
- The guard must treat the stage mismatch as a workflow-process problem, even
  when the implementation files are otherwise valid and all code-quality checks
  pass.
- Valid documentation-only spec and plan PRs must continue through the existing
  review, CI, label, and tracker flow without extra human intervention.
- Resume paths must evaluate the current PR diff, not only newly generated files
  from the current agent run.
- The implementation plan must define any allowed exception or override path
  explicitly; absence of an explicit exception means the automatic ready path
  stays blocked.

## Operational Visibility

- **PR warning**: A stage-mismatched documentation PR shows a warning comment or
  equivalent PR-visible status that explains the mismatch and lists the
  unexpected files.
- **Runner summary**: The Work Item Runner reports the stage-alignment result in
  its terminal summary when the guard blocks readiness or requires human
  decision.
- **Review handoff**: Human reviewers can distinguish this workflow-process
  blocker from ordinary code-quality reviewer feedback.
- **Verification evidence**: The implementation PR includes tests or smoke
  evidence for aligned and mismatched documentation-stage PR examples.

## Acceptance Criteria

- [ ] A plan-stage PR that changes only expected plan/spec documentation
      artifacts can continue through the existing readiness path.
- [ ] A plan-stage PR that includes implementation artifacts is detected before
      automatic `ready-for-human-review` labeling.
- [ ] A spec-stage PR that includes implementation artifacts is detected before
      automatic `ready-for-human-review` labeling.
- [ ] When a documentation-stage PR is stage-mismatched, the workflow produces a
      PR-visible warning that names the expected stage and lists the unexpected
      files or file categories.
- [ ] When a documentation-stage PR is stage-mismatched, the Work Item Runner
      does not report the item as ready for human review unless the mismatch has
      been corrected, explicitly resolved, or escalated.
- [ ] The warning message makes clear that the issue is workflow stage collapse,
      not necessarily code correctness.
- [ ] Resume behavior evaluates the current PR diff so a contaminated existing
      plan or spec branch cannot bypass the guard.
- [ ] Valid documentation-only spec and plan PRs are not blocked by the guard.
- [ ] The implementation plan documents the selected enforcement mechanism and
      any explicit override or exception path.
- [ ] Verification coverage includes at least one mismatched plan PR example,
      one mismatched spec PR example, and one aligned documentation-stage PR
      example.

## Coverage Matrix

| Brief objective | Coverage |
| --- | --- |
| 1. Detect plan-stage PR files outside expected documentation scope | Use Case 1, Use Case 3, Business Rules, AC1, AC2, AC7, AC8 |
| 2. Prevent automatic readiness handoff for plan PRs with implementation files | Use Case 1, Business Rules, AC2, AC5 |
| 3. Notify reviewers and runner with a clear warning and unexpected file list | Use Case 2, Operational Visibility, AC4, AC6 |
| 4. Cover spec-stage PRs with the same stage-alignment expectation | Use Case 4, Business Rules, AC3, AC8, AC10 |
| 5. Let the implementation plan choose the enforcement mechanism | Business Rules, Out of Scope, AC9 |
| 6. Protect restarted or resumed agent runs from inherited contamination | Use Case 3, Business Rules, AC7 |

## Out of Scope (MVP)

- Choosing the exact technical implementation for the guard, such as whether it
  lives in the item runner, reviewer loop, CI, or a combination. **Deferral
  Note**: the issue explicitly allows multiple implementation shapes, and the
  accepted checkpoint for this spec asks the implementation plan to make that
  decision.
- Defining the full file-path allowlist or classification algorithm for every
  downstream repository shape. **Deferral Note**: the spec requires the product
  behavior and evidence surfaced to humans; the implementation plan should
  define the precise matching rules and extension points.
- Rewriting already-accepted downstream PRs that contained implementation code
  on plan branches. **Deferral Note**: this feature prevents future silent
  readiness handoff; historical remediation remains a separate operational
  decision.
- Changing code-quality reviewer behavior for implementation PRs. **Deferral
  Note**: the problem is stage alignment before human handoff, not whether
  implementation code passes normal review.

## PR-Visible Deferral Notes

- **Exact gate mechanism**: Deferred to the implementation plan so the plan can
  choose protocol gating, CI enforcement, or a combined approach based on the
  existing workflow surfaces.
- **Precise documentation-stage file boundary**: Deferred to the implementation
  plan, which must define the expected file categories and any downstream
  extension points.
- **Historical PR remediation**: Deferred because the MVP is forward-looking
  prevention and readiness blocking for future or resumed PRs.
