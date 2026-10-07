# Consumer Workflow Test Portability — Spec

**Issue**: [#1873](https://github.com/lhpaul/ai-dev-framework-template/issues/1873)

## Overview

Maintainers must be able to synchronize the workflow into a consumer repository
and run its shipped tests without failures caused by the template repository's
own settings or historical documents. The correction preserves tests of shared
workflow behavior and the template's own default-policy checks.

## Use Cases

### Use Case 1: Validate a synchronized consumer

**Actor**: Consumer maintainer.
**Preconditions**: The shared workflow has been synchronized; the repository is
declared a consumer, has its own reviewer selection and guidance, and lacks the
template's historical development documents and smoke runbooks.

**Steps**:

1. Run the affected shipped workflow test suites.
2. Read each suite's result and any explicit template-only skip.

**Postconditions**: Repository-specific differences do not produce false
failures. Tests of shared behavior still execute.

**Information shown**: Test pass/fail results and explicit skips.
**Actions available**: Investigate a real failing assertion or continue validation.
**Considerations**: Missing template history must not abort the reviewer tests.

### Use Case 2: Validate the template

**Actor**: Template maintainer.
**Preconditions**: The repository is declared a template.

**Steps**:

1. Run the same affected suites, including their supported planted violations.
2. Confirm that violations of the template's shipped reviewer policy and shared
   guidance are detected.

**Postconditions**: Template-only checks remain effective, and shared framework
behavior has equivalent coverage in both repository modes.

**Information shown**: Passing baselines and detected planted violations.
**Actions available**: Repair real regressions before distributing the workflow.
**Considerations**: A consumer configuration must not bypass shared logic tests.

## Business Rules

- Consumer-owned configuration, agent guidance, and historical documents are
  independent of the template's current repository state.
- Assertions about template defaults apply only to the template.
- Shared behavior must be tested using controlled inputs rather than depending
  on the receiving repository's mode.
- Any skipped template-only assertion must be visible in test output.

## Acceptance Criteria

- [ ] AC1: The affected suites pass in a consumer with its own reviewer selection.
- [ ] AC2: A consumer without template development documents or historical smoke
  runbooks can complete the affected suites.
- [ ] AC3: Framework-mode routing and backlog-creation refusal checks retain
  their positive and negative coverage in both repository modes.
- [ ] AC4: Template reviewer-policy and shared-guidance violations remain
  detectable through the affected suites' planted-violation checks.
- [ ] AC5: Template-only skips are explicit; shared assertions still execute in
  consumers, and the template baseline remains green.

## Out of Scope (MVP)

- Changing runtime routing, tracker classification, or reviewer policy.
- Repairing unrelated post-merge advisory automation.
- A new CI job for a synthetic consumer tree; local consumer validation is
  required here, while CI automation may be considered separately.
- Synchronizing project-owned guidance or template historical documents.
