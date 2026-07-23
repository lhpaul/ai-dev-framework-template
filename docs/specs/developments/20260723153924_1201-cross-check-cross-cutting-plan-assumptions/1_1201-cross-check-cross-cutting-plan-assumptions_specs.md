# Cross-Check Cross-Cutting Plan Assumptions - Spec

---

## Overview

Plans created while multiple workflow items are in flight must not silently
encode operational assumptions that another item or pull request is changing.
When a plan relies on a cross-cutting operational fact, the planning workflow
records the fact's source and verification time, checks the bounded current-batch
context for a conflict, and requires the parent orchestrator to resolve any
conflict before implementation begins. Plans without such assumptions record a
short not-applicable result without scanning the entire repository portfolio.

## Brief Objective List

1. Record the source and verification time for every applicable cross-cutting
   operational assumption used by a plan.
2. Check current-batch items and plausibly related open pull requests for changes
   to the same assumption surface.
3. Surface conflicting in-flight evidence to the parent orchestrator and stop
   implementation until the conflict is resolved.
4. Re-verify applicable operational assumptions before implementation begins.
5. Let plans with no cross-cutting operational assumptions record a concise
   not-applicable result without an unbounded pull-request scan.

## Use Cases

### Use Case 1: Planner verifies an applicable operational assumption

**Actor**: Workflow planner preparing an implementation plan.
**Preconditions**: The plan relies on a cross-cutting operational fact, such as
an environment target, linked cloud project, approved base branch, or canonical
configuration.

**Steps**:

1. The planner identifies the operational assumption on which the plan relies.
2. The planner records the assumption, its authoritative source, and when it was
   verified.
3. The planner checks the items in the current batch and plausibly related open
   pull requests for work that changes the same assumption surface.
4. The planner records whether the bounded cross-check found consistent
   evidence or a conflict.
5. If the evidence is consistent, the planner completes the plan with the
   verified assumption visible for later re-verification.

**Postconditions**: The plan exposes the assumption and its provenance instead
of presenting a potentially stale operational fact as timeless truth.

**Information shown**:

- The operational assumption in plain language.
- The authoritative source used to verify it.
- The verification time.
- The bounded cross-check scope and result.

**Actions available**:

- Continue plan writing when the evidence is consistent.
- Escalate a conflict to the parent orchestrator.
- Correct or remove an unsupported assumption.

**Considerations**:

- Shared terminology alone is not evidence that another item changes the same
  assumption surface.
- The check is bounded to current-batch context and plausibly related open pull
  requests, rather than every open pull request in the repository.
- A source that cannot be verified is treated as unresolved evidence, not as
  confirmation.

### Use Case 2: Parent orchestrator resolves conflicting in-flight evidence

**Actor**: Parent orchestrator supervising the workflow item.
**Preconditions**: The planner found another current-batch item or plausibly
related open pull request that may change an operational assumption used by the
plan.

**Steps**:

1. The planner reports the assumption, its source, the conflicting evidence,
   and the affected plan statements.
2. The parent orchestrator compares the competing evidence.
3. The parent orchestrator records which interpretation is authoritative or
   requests a human decision when the conflict cannot be resolved safely.
4. The planner updates the plan to reflect the resolution and its provenance.
5. The workflow keeps implementation blocked until the resolution is recorded.

**Postconditions**: Implementation does not begin from a plan whose applicable
operational assumption is known to conflict with in-flight work.

**Information shown**:

- The assumption surface in conflict.
- The relevant current-batch item or pull request.
- The competing values or interpretations.
- The recorded resolution and decision owner.

**Actions available**:

- Select the authoritative interpretation when evidence is sufficient.
- Ask the human to resolve an ambiguous conflict.
- Return the plan for correction.

**Considerations**:

- A conflict is a workflow stop, not an instruction to guess which source will
  eventually win.
- Resolution of one assumption does not imply that unrelated assumptions were
  verified.

### Use Case 3: Implementer re-verifies a previously recorded assumption

**Actor**: Workflow implementer beginning work from an approved plan.
**Preconditions**: The plan records one or more applicable operational
assumptions.

**Steps**:

1. Before implementation work begins, the implementer reads each recorded
   assumption and its verification evidence.
2. The implementer re-verifies the assumption against its recorded
   authoritative source.
3. If the assumption is unchanged, implementation proceeds.
4. If it changed or now conflicts with in-flight work, the implementer stops
   and returns the conflict to the parent orchestrator for resolution.

**Postconditions**: Implementation uses current operational facts rather than
assuming the plan-time snapshot is still valid.

**Information shown**:

- The plan-time verification record.
- The current verification result.
- Any changed or conflicting evidence.

**Actions available**:

- Proceed when the assumption remains valid.
- Stop and request conflict resolution when it does not.

**Considerations**:

- Re-verification is required at implementation start because an assumption can
  become stale after plan approval.
- The check does not reopen unrelated product or architecture decisions.

### Use Case 4: Planner records that the cross-check is not applicable

**Actor**: Workflow planner whose plan has no cross-cutting operational
assumption.
**Preconditions**: The plan does not rely on an environment target, linked
external resource, approved base branch, canonical configuration, or another
operational fact that concurrent work could invalidate.

**Steps**:

1. The planner evaluates whether the plan relies on a cross-cutting operational
   assumption.
2. The planner records a short not-applicable result and the reason.
3. The planner proceeds without a repository-wide pull-request scan.

**Postconditions**: The workflow retains visible evidence that applicability was
considered without creating unnecessary portfolio-wide work.

**Information shown**:

- A concise not-applicable result.
- The reason no operational assumption cross-check is needed.

**Actions available**:

- Continue plan writing.
- Reclassify the check as applicable if later plan content introduces such an
  assumption.

**Considerations**:

- The not-applicable path is not valid merely because related pull requests are
  inconvenient to inspect.

## Business Rules

- The cross-check is required only when a plan relies on a cross-cutting
  operational assumption that concurrent work could invalidate.
- Applicable assumptions include, but are not limited to, environment targets,
  linked cloud projects, approved base branches, and canonical configuration
  values.
- Every applicable assumption must identify its authoritative source and
  verification time.
- The planner must check current-batch items and plausibly related open pull
  requests that may change the same assumption surface.
- The planner must not substitute an unbounded scan of every open pull request
  for the bounded relevance check.
- A detected conflict or unverifiable source must be recorded and resolved by
  the parent orchestrator before implementation begins.
- The implementer must re-verify every applicable assumption at implementation
  start.
- A plan with no applicable assumption must record a concise not-applicable
  result and rationale, without performing a repository-wide pull-request scan.
- Shared keywords alone do not establish a conflict; the evidence must concern
  the same operational assumption surface.

## Operational Visibility

- **Plan evidence**: Each applicable assumption shows its value, source,
  verification time, bounded cross-check scope, and result.
- **Conflict record**: The parent orchestrator can see the affected assumption,
  competing evidence, resolution status, and decision owner.
- **Implementation gate**: The workflow records the implementation-start
  re-verification result before implementation proceeds.
- **Not-applicable evidence**: Plans without applicable assumptions show a
  concise rationale instead of silently skipping the check.

## Acceptance Criteria

- [ ] AC1: Given a plan relies on a cross-cutting operational assumption, the
      plan records the assumption, its authoritative source, and verification
      time.
- [ ] AC2: Given an applicable assumption, the planner checks current-batch
      items and plausibly related open pull requests for changes to the same
      assumption surface and records the bounded scope and result.
- [ ] AC3: Given the bounded cross-check finds conflicting evidence, the plan
      records the conflict and implementation remains blocked until the parent
      orchestrator records a resolution.
- [ ] AC4: Given the parent orchestrator cannot resolve a conflict from
      available evidence, the workflow requests a human decision rather than
      choosing an assumption silently.
- [ ] AC5: Given implementation is about to begin from a plan with applicable
      assumptions, each assumption is re-verified against its recorded source
      before implementation work proceeds.
- [ ] AC6: Given implementation-start re-verification finds a changed or
      conflicting assumption, implementation stops and returns the conflict to
      the parent orchestrator.
- [ ] AC7: Given a plan has no cross-cutting operational assumption, the plan
      records a concise not-applicable result and rationale without scanning
      every open pull request.
- [ ] AC8: Given another item or pull request merely shares terminology with the
      plan, the workflow does not classify it as a conflict unless it changes
      the same operational assumption surface.

## Cross-Cutting Assumption Gate Consistency Matrix

| Gate input | Allowed outcome | Required next action | Workflow surface | Example |
| --- | --- | --- | --- | --- |
| Plan relies on an applicable cross-cutting operational assumption and bounded evidence is consistent | Verified | Record the assumption, source, verification time, bounded scope, and result; continue planning | Planning guidance and plan review | An approved base branch agrees with the current-batch context and related open PRs |
| Plan relies on an applicable assumption and bounded evidence conflicts | Conflict | Record competing evidence and stop implementation pending parent-orchestrator resolution | Planning guidance, plan review, and item orchestration | A related PR changes the linked cloud project named by the plan |
| Parent orchestrator has sufficient evidence to resolve the conflict | Resolved | Record the authoritative interpretation and decision owner; update the plan | Item orchestration and plan artifact | The owning configuration identifies one environment target as authoritative |
| Parent orchestrator lacks sufficient evidence | Human decision required | Stop and request a human decision | Item orchestration | Competing sources identify different canonical configuration values |
| Plan has no applicable cross-cutting operational assumption | Not applicable | Record a concise rationale; do not perform a repository-wide pull-request scan | Planning guidance and plan review | A prose-only plan introduces no environment, branch, linked-resource, or canonical-configuration assumption |
| Implementation-start re-verification matches the recorded source | Still valid | Record the result and begin implementation | Implementation guidance and item orchestration | The recorded environment target remains unchanged |
| Implementation-start re-verification changed or conflicts | Stale or conflicting | Stop implementation and return the conflict to the parent orchestrator | Implementation guidance and item orchestration | The approved base branch changed after plan approval |

## Coverage Matrix

| Brief objective | Covered by | Acceptance criteria |
| --- | --- | --- |
| 1. Record source and verification time for applicable assumptions | Use Case 1, Business Rules, Operational Visibility | AC1 |
| 2. Check current-batch items and plausibly related open PRs | Use Case 1, Business Rules | AC2, AC8 |
| 3. Resolve detected conflicts before implementation | Use Case 2, Business Rules, Operational Visibility | AC3, AC4 |
| 4. Re-verify assumptions before implementation | Use Case 3, Business Rules | AC5, AC6 |
| 5. Record not-applicable without an unbounded scan | Use Case 4, Business Rules | AC7 |

## Out of Scope (MVP)

- Defining the technical query, matching algorithm, or storage format used to
  find plausibly related pull requests.
- Automatically proving that every operational assumption in a plan has been
  discovered.
- Scanning all open pull requests or all tracker items for every plan.
- Resolving unrelated product, architecture, or implementation decisions.
- Changing existing reviewer, CI, merge-authority, or tracker-status policy
  beyond the assumption-conflict stop described here.
