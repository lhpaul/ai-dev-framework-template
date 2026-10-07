# Pipefail-safe test assertions — Spec

**Issue**: [#1877](https://github.com/lhpaul/ai-dev-framework-template/issues/1877)

## Overview

Framework maintainers and downstream consumers need text assertions that report
whether the expected text is present, regardless of output size or pipe-buffer
timing. This correction removes premature-reader-exit failures from existing
test assertions and prevents contributors from reintroducing that unsafe pattern.

## Use Cases

### Use Case 1: Validate captured output reliably

**Actor**: Framework maintainer or downstream contributor.
**Preconditions**: A test checks captured command output for expected text.

**Steps**:

1. Run the affected test suite with pipeline-failure propagation enabled.
2. Check both output containing the expected text and output without it.
3. Repeat the check with output larger than a pipe buffer.

**Postconditions**: Matching output passes and missing text fails; a reader
finishing early cannot turn a successful text match into an assertion failure.

**Information shown**: The existing assertion names and pass/fail diagnostics.
**Actions available**: Inspect and correct genuine assertion failures.
**Considerations**: Case-insensitive, fixed-string, line-anchored, negative, and
filtered-output assertions retain their existing matching expectations.

### Use Case 2: Detect recurrence before integration

**Actor**: Contributor changing framework shell tests.
**Preconditions**: The contributor introduces or modifies an unsafe assertion.

**Steps**:

1. Run the existing shell validation gate on the proposed change.
2. Read the diagnostic locating the unsafe assertion.
3. Replace it with an assertion that safely reads its input and rerun validation.

**Postconditions**: Validation rejects the unsafe assertion and accepts its safe
replacement. Intentional examples and fixtures do not prevent safe tests from
being integrated.

**Information shown**: File, line, rule identifier, and corrective guidance.
**Actions available**: Correct the assertion or document an intentional exception
using the validation gate's existing local exception mechanism.

## Business Rules

- Preserve assertion names, expected values, match options, and test coverage.
- Correct every affected assertion in the repository's shell-test tree,
  including shared test helpers and embedded executable test mocks.
- Reuse the current shell validation gate and supported runtime baseline.
- Downstream consumers receive the same safe assertions and lint behavior
  through the existing template synchronization surfaces.

## Acceptance Criteria

- [ ] AC1: The reported help-text assertion and neighboring help assertions
  succeed for matching output larger than a pipe buffer and reject absent text.
- [ ] AC2: A repository-wide test-tree audit finds no untreated unsafe assertion;
  any intentional residual has an explicit reason and safe execution context.
- [ ] AC3: Shell validation rejects a newly added unsafe assertion with a file,
  line, and corrective diagnostic, and accepts its safe replacement.
- [ ] AC4: Affected suites retain their expectations and pass on the supported
  shell baseline; committed regression coverage proves the large-output case.
- [ ] AC5: The validation rule has positive and negative examples, including
  option variants, filtered input, continued commands, and intentional fixtures.

## Brief Objective List and Coverage Matrix

| Brief objective | Coverage |
| --- | --- |
| Fix the reported flaky help check and neighboring assertions | AC1, AC4 |
| Treat equivalent assertions throughout the test tree | AC2, AC4 |
| Prevent recurrence with lint | AC3, AC5 |

No brief objective is deferred.

## Out of Scope (MVP)

- Changes to production workflow command behavior or a production-wide pipe audit.
- Fixing the unrelated closing-keyword workflow failure after PR #1896.
- New external services, consumer-specific configuration, or pipeline policies.
- A complete shell parser or a blanket ban on pipes in tests.
