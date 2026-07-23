# Portable Documentation-Stage Alignment Hardening - Spec

---

## Overview

Documentation-stage alignment protects the staged workflow from pull requests
that contain artifacts outside the selected documentation stage. This change
hardens that protection so path traversal cannot make a disallowed artifact
look permitted and so alignment results remain dependable across macOS, GNU,
and BusyBox environments. Operators must receive an explicit failure when the
checker cannot evaluate an input rather than a misleading alignment result.

## Brief Objective List

1. Reject malicious or accidental parent-directory traversal in plan-stage
   path evaluation.
2. Preserve acceptance of legitimate plan-stage smoke-test documentation.
3. Produce the same content-decoding result on macOS, GNU, and BusyBox
   environments.
4. Prevent decoding failures from being silently interpreted as stage
   alignment results.
5. Add automated coverage for traversal paths and supported environment
   families.

## Use Cases

### Use Case 1: Validate plan-stage changed paths

**Actor**: Workflow operator advancing an implementation-plan pull request.
**Preconditions**: The documentation-stage alignment gate is evaluating the
pull request's changed paths for the plan stage.

**Steps**:

1. The workflow evaluates every changed path against the plan-stage artifact
   policy.
2. A canonical smoke-test documentation path is accepted when it is otherwise
   valid for the plan stage.
3. Any path containing a parent-directory traversal segment is rejected,
   including a path that begins with an otherwise permitted directory.
4. The workflow reports the resulting alignment decision.

**Postconditions**: A disallowed artifact cannot enter the plan stage by using
parent-directory traversal, while valid plan-stage artifacts continue through
the existing workflow.

**Information shown**:

- Whether documentation-stage alignment passed, mismatched, or could not be
  evaluated.
- The offending path when a path violates the stage policy.

**Actions available**:

- Correct a mismatched pull-request diff and re-run the gate.
- Retry or repair the checker environment when evaluation could not complete.

**Considerations**:

- Traversal is rejected before a permitted prefix or filename pattern can make
  the path appear valid.
- Both malicious input and accidental malformed paths receive the same safe
  rejection behavior.

### Use Case 2: Evaluate content consistently across supported environments

**Actor**: Workflow operator or CI system running documentation-stage
alignment.
**Preconditions**: The gate receives encoded repository content that it must
inspect to determine alignment.

**Steps**:

1. The workflow evaluates the encoded content in a macOS, GNU, or BusyBox
   environment.
2. A valid payload produces the same decoded content and alignment decision in
   each supported environment family.
3. An invalid payload or unavailable decoding capability produces an explicit
   evaluation failure.
4. The workflow reports the failure without presenting it as a clean alignment
   result or an ordinary documentation mismatch.

**Postconditions**: Environment-specific command behavior cannot silently
change the alignment outcome.

**Information shown**:

- The alignment result for successfully evaluated content.
- An actionable error when content evaluation cannot be completed.

**Actions available**:

- Continue the workflow after a successful alignment result.
- Correct the payload or checker environment and retry after an evaluation
  failure.

**Considerations**:

- The implementation technique for portable decoding is selected during
  implementation planning.
- A successful command probe must demonstrate actual decoding behavior rather
  than relying only on command-help text.

## Business Rules

- A changed path containing a parent-directory traversal segment must never be
  accepted by a documentation-stage allowlist.
- Canonical plan-stage smoke-test documentation paths that satisfy the existing
  policy must remain accepted.
- Equivalent valid encoded content must produce equivalent decoded content and
  alignment decisions on macOS, GNU, and BusyBox environments.
- Content-decoding failure must be visible and must not be converted into a
  clean result, an empty-content result, or an ordinary stage mismatch.
- The gate must distinguish an invalid pull-request artifact from an
  infrastructure failure that prevented evaluation.
- Existing documentation-stage artifact policies remain unchanged except for
  rejecting traversal and eliminating environment-dependent decoding.
- Automated checks must cover accepted paths, traversal paths, valid payloads,
  invalid payloads, and each supported environment family.

## Operational Visibility

- **Alignment output**: The existing human-readable and machine-readable gate
  outputs identify pass, mismatch, and evaluation-failure outcomes.
- **Path evidence**: A rejected path is included in the mismatch evidence so
  the operator can correct the pull-request diff.
- **Infrastructure evidence**: A decoding failure identifies content
  evaluation as the cause and provides a non-success outcome suitable for CI
  and orchestration.
- **Auditability**: Automated coverage demonstrates that the same representative
  payload is handled consistently in macOS, GNU, and BusyBox environments.

## Workflow Decision-Gate Matrix

| Gate inputs | Allowed outcome | Required next action | Mirror surfaces | Example / rationale |
| --- | --- | --- | --- | --- |
| Plan stage and canonical permitted smoke-test path | Aligned | Continue the normal documentation readiness flow | Alignment helper output, tests, and workflow readiness guidance | A direct smoke-test document path remains permitted |
| Plan stage and path containing a parent-directory traversal segment | Mismatch | Identify the path, correct the diff, and re-run alignment | Alignment helper output, tests, and workflow readiness guidance | A permitted prefix followed by parent traversal must not bypass the stage boundary |
| Supported environment and valid encoded content | Evaluated | Use the decoded content in the normal alignment decision | Alignment helper output and cross-environment tests | The representative payload has one consistent result across macOS, GNU, and BusyBox |
| Supported environment and invalid encoded content | Evaluation failure | Stop readiness, report the content failure, and retry after correction | Alignment helper output, CI behavior, tests, and workflow readiness guidance | Invalid content is not equivalent to an empty or mismatched artifact |
| Environment cannot perform the required decoding | Evaluation failure | Stop readiness, report the environment limitation, and repair or replace the capability | Alignment helper output, CI behavior, tests, and workflow readiness guidance | Silent fallback is not an allowed outcome |

## Acceptance Criteria

- [ ] AC1: Given a plan-stage path that contains a parent-directory traversal
      segment, documentation-stage alignment rejects the path even when it
      starts with an otherwise permitted directory.
- [ ] AC2: Given canonical plan-stage smoke-test documentation paths,
      documentation-stage alignment continues to accept them according to the
      existing stage policy.
- [ ] AC3: Given the same valid representative encoded payload on macOS, GNU,
      and BusyBox environments, the checker produces equivalent decoded content
      and the same alignment decision.
- [ ] AC4: Given invalid encoded content, the checker returns a visible
      non-success evaluation failure and does not report clean alignment,
      empty content, or an ordinary stage mismatch.
- [ ] AC5: Given the environment cannot perform the required decoding, the
      checker returns a visible infrastructure failure with actionable context.
- [ ] AC6: Automated tests cover canonical accepted paths, at least one
      traversal path after a permitted prefix, valid and invalid encoded
      payloads, and macOS, GNU, and BusyBox decoding behavior.
- [ ] AC7: Existing documentation-stage alignment outcomes remain unchanged for
      inputs that do not contain traversal and can be decoded successfully.
- [ ] AC8: Human-readable and machine-readable gate evidence distinguish
      artifact mismatch from evaluation failure.

## Coverage Matrix

| Brief objective | Covered by | Acceptance criteria |
| --- | --- | --- |
| Reject malicious or accidental parent-directory traversal in plan-stage path evaluation | Use Case 1, Business Rules, Decision-Gate Matrix | AC1, AC6 |
| Preserve acceptance of legitimate plan-stage smoke-test documentation | Use Case 1, Business Rules | AC2, AC7 |
| Produce the same content-decoding result on macOS, GNU, and BusyBox environments | Use Case 2, Business Rules, Operational Visibility | AC3, AC6 |
| Prevent decoding failures from being silently interpreted as alignment results | Use Case 2, Business Rules, Decision-Gate Matrix | AC4, AC5, AC8 |
| Add automated coverage for traversal paths and supported environment families | Business Rules, Operational Visibility | AC6 |

## Out of Scope (MVP)

- Changing which canonical artifact categories belong to the spec, plan, or
  implementation stages.
- Replacing the documentation-stage alignment workflow or changing its
  readiness-label and tracker-transition contract.
- Defining the technical decoding implementation; the implementation plan
  selects the portable mechanism that satisfies this specification.
- General-purpose filesystem sandboxing beyond the paths evaluated by the
  documentation-stage alignment gate.
- Backporting the change into downstream repositories as part of this item.
