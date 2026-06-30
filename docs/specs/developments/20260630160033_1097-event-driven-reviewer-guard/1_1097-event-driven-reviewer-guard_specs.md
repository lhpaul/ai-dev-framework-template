# Event-Driven Reviewer Guard Readiness - Spec

**Epic**: #1095 Actions cost reduction

---

## Overview

Workflow maintainers need the reviewer-loop readiness guarantee without spending
GitHub-hosted runner minutes on long guard waits. This feature changes the guard
experience so readiness is confirmed by a short, event-driven signal tied to the
reviewer-loop summary instead of default long polling on pull request updates.

The product outcome is the same for operators: a pull request is considered
ready only when the canonical reviewer-loop summary exists for the relevant
review state. The cost profile changes because missing-summary cases fail or
remain pending quickly rather than sleeping for several minutes on every default
guard run.

## Brief Objective List

Derived from issue #1097:

1. Remove the default several-minute guard sleep or polling path from
   GitHub-hosted runners.
2. Preserve the merge-readiness guarantee currently provided by the reviewer-loop
   summary guard.
3. Keep the canonical summary markers as the source of truth unless a documented
   replacement is explicitly introduced.
4. Keep fast validation behavior for pull requests outside implementation branch
   prefixes.
5. Update branch-protection and readiness guidance for the new readiness signal.
6. Cover missing-summary, summary-present, and out-of-scope branch cases with
   tests.

---

## Use Cases

### Use Case 1: Implementation PR becomes ready after the reviewer loop finishes

**Actor**: Workflow operator running `/run-reviewer-loop`, `/run-item`, or
`/run-epic`.
**Preconditions**: An implementation pull request exists and requires reviewer
loop readiness before merge.

**Steps**:

1. The operator runs the normal reviewer loop.
2. The reviewer loop completes its configured review platforms.
3. The reviewer loop posts the canonical automated reviewer-loop summary.
4. The readiness guard records or validates the summary-present signal without a
   long default wait.
5. The pull request exposes a passing readiness result for merge policy.

**Postconditions**: The pull request has a visible readiness result that confirms
the reviewer-loop summary exists for the current review state.

**Information shown**:

- The reviewer-loop summary comment.
- A concise readiness result that branch protection or merge gates can use.
- Any reviewer-loop platform findings as usual.

**Actions available**:

- Continue to merge-gate evaluation when the readiness result is passing.
- Rerun the reviewer loop if the summary is missing or stale.

**Considerations**:

- Operators should not need to understand the underlying event mechanism to know
  whether readiness passed.

### Use Case 2: Implementation PR is missing the reviewer-loop summary

**Actor**: Workflow operator, automation, or branch protection check.
**Preconditions**: An implementation pull request is open, but no valid
automated reviewer-loop summary is present.

**Steps**:

1. The pull request receives an update or readiness validation is requested.
2. The readiness guard checks for the canonical reviewer-loop summary.
3. The guard does not spend several minutes polling by default.
4. The readiness result remains non-passing or reports a clear missing-summary
   state.

**Postconditions**: The pull request cannot be treated as reviewer-loop ready
until the reviewer loop posts the required summary.

**Information shown**:

- A missing-summary readiness result or equivalent non-passing signal.
- Guidance that the reviewer loop must be run.

**Actions available**:

- Run `/run-reviewer-loop`, `/run-item`, or `/run-epic`.
- Recheck readiness after the summary is posted.

**Considerations**:

- Missing-summary behavior must be deterministic enough for automation to avoid
  treating "not yet checked" as "ready".

### Use Case 3: Non-implementation PR uses the fast validation path

**Actor**: Workflow operator or contributor opening a spec, plan, documentation,
or other out-of-scope pull request.
**Preconditions**: A pull request branch does not require the implementation
reviewer-loop readiness gate.

**Steps**:

1. The pull request is opened or updated.
2. The readiness guard determines that the branch is outside the guarded
   implementation scope.
3. The guard exits quickly with a passing or skipped-equivalent result according
   to existing workflow semantics.

**Postconditions**: Out-of-scope pull requests do not spend runner minutes on a
guard that is not required for their branch type.

**Information shown**:

- A fast result that the guarded readiness path does not apply.

**Actions available**:

- Continue the normal spec, plan, or documentation review path.

**Considerations**:

- This must not weaken implementation-branch readiness requirements.

### Use Case 4: Downstream maintainer configures branch protection

**Actor**: Downstream template maintainer.
**Preconditions**: A downstream repository syncs the template and uses branch
protection or merge-gate checks for reviewer-loop readiness.

**Steps**:

1. The maintainer reads the updated readiness guidance.
2. The guidance identifies the readiness signal that should be required.
3. The maintainer can distinguish the new short readiness path from the old
   long-polling guard behavior.
4. The maintainer configures or verifies branch protection accordingly.

**Postconditions**: Downstream repositories keep reviewer-loop readiness without
inheriting avoidable default runner-minute waits.

**Information shown**:

- The recommended readiness check or status name.
- When the readiness result appears.
- How missing-summary and out-of-scope cases behave.

**Actions available**:

- Keep the template default.
- Adjust branch protection to require the documented readiness signal.
- Run reviewer-loop commands when readiness is missing.

**Considerations**:

- Guidance must be explicit enough that downstream projects do not accidentally
  require a removed or obsolete long-polling check.

---

## Business Rules

- The default guard path must not sleep or poll for several minutes on
  GitHub-hosted runners.
- Implementation pull requests must still require a valid reviewer-loop summary
  before they can be treated as reviewer-loop ready.
- The canonical automated reviewer-loop summary markers remain the readiness
  source of truth unless a replacement is explicitly documented.
- A missing reviewer-loop summary must not be reported as ready.
- Pull requests outside the guarded implementation scope must continue to receive
  a fast non-blocking readiness result.
- Readiness behavior must be visible enough for branch protection, merge gates,
  and human operators to understand why a pull request is ready or not ready.

---

## Operational Visibility

- **Reviewer-loop summary**: Remains visible on the pull request and continues
  to explain clean, blocking, skipped, and advisory reviewer outcomes.
- **Readiness signal**: Shows whether the summary-present condition is satisfied
  without relying on a long default polling window.
- **Missing-summary state**: Makes it clear that the reviewer loop needs to run
  or needs to post its summary.
- **Out-of-scope state**: Makes it clear when the guarded readiness path does not
  apply to the pull request branch.
- **Documentation**: Explains the readiness signal downstream maintainers should
  use for branch protection or merge checks.

---

## Acceptance Criteria

- [ ] Default reviewer-loop guard execution does not sleep or poll for several
      minutes on GitHub-hosted runners.
- [ ] Implementation pull requests with a valid reviewer-loop summary receive a
      passing readiness result.
- [ ] Implementation pull requests without a valid reviewer-loop summary do not
      receive a passing readiness result.
- [ ] Pull requests outside implementation branch scope complete the guard path
      quickly and preserve existing non-blocking semantics.
- [ ] The reviewer-loop summary marker remains the documented source of truth for
      readiness, unless the implementation plan introduces and documents a
      replacement signal.
- [ ] Branch-protection and readiness documentation identifies the result
      downstream repositories should require.
- [ ] Tests cover missing-summary, summary-present, and out-of-scope branch
      cases.

---

## Coverage Matrix

| Brief objective | Covered by | Acceptance criteria |
| --- | --- | --- |
| Remove default several-minute guard waits | Use Cases 1 and 2, Business Rules | AC1 |
| Preserve reviewer-loop readiness guarantee | Use Cases 1 and 2, Business Rules | AC2, AC3 |
| Keep canonical summary markers as source of truth | Business Rules, Operational Visibility | AC5 |
| Keep fast out-of-scope validation | Use Case 3, Business Rules | AC4 |
| Update branch-protection/readiness guidance | Use Case 4, Operational Visibility | AC6 |
| Cover required cases with tests | Acceptance Criteria | AC7 |

---

## Out of Scope

- Replacing the reviewer-loop summary with a different product contract unless
  the implementation plan proves and documents an equivalent readiness signal.
- Changing which reviewer platforms are configured for the reviewer loop.
- Changing merge authority, risk policy, or human review requirements for
  `/run-epic`, `/run-item`, or `/run-reviewer-loop`.
- Optimizing unrelated Actions workflows outside the reviewer-loop readiness
  guard.

---

## PR-Visible Deferral Notes

- The implementation plan may choose the exact readiness mechanism, such as a
  short summary-comment event path, a commit status, a check run, or another
  documented signal, as long as the product-facing readiness guarantees above are
  preserved.
- Detailed branch-protection migration wording belongs in the implementation
  plan and documentation update, not in this product spec.
