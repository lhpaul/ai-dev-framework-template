# One External Reviewer Practice - Spec

**Epic**: #1112 External review loop - Haystack advisory hardening

---

## Overview

Workflow maintainers need a clear recommended pattern for external automated
reviewers. The template currently supports multiple external reviewer lists, but
downstream teams often get better cost, latency, and signal quality from one
external reviewer per repository or product plus the runner's internal review
gate.

This feature documents that recommended operating model while still allowing
multi-bot configurations for teams that intentionally accept the extra
coordination overhead. The guidance should help maintainers choose review
configuration defaults without reading individual protocol internals.

## Brief Objective List

Derived from issue #1117:

1. Update external review documentation with the recommended pattern: one
   external reviewer per repository or product plus internal runner reviewers.
2. Document multi-bot configurations as advanced usage and call out cost,
   latency, and conflict trade-offs.
3. Optionally warn when a workflow configuration lists more than one external
   reviewer in a phase, as a non-blocking warning.

## Use Cases

### Use Case 1: Maintainer chooses a reviewer configuration

**Actor**: Workflow maintainer.
**Preconditions**: The repository uses automated pull request review and has a
workflow configuration.

**Steps**:

1. The maintainer reads the external reviewer guidance.
2. The maintainer identifies the recommended default operating model.
3. The maintainer configures one external reviewer for the repository or product.
4. The maintainer relies on internal runner review for the remaining review gate.

**Postconditions**: The repository has a review configuration that follows the
recommended default unless the maintainer intentionally chooses an advanced
multi-bot setup.

**Information shown**:

- The recommended one-external-reviewer pattern.
- The role of internal runner review alongside external reviewers.
- The trade-offs of adding additional external reviewers.

**Actions available**:

- Adopt the recommended one-external-reviewer pattern.
- Choose a multi-bot setup when the team accepts the trade-offs.
- Review configuration warnings when they are available.

**Considerations**:

- The recommendation should not remove existing multi-reviewer support.
- The guidance should apply to both repository-level and product-level review
  configuration.

### Use Case 2: Maintainer intentionally uses multiple external reviewers

**Actor**: Workflow maintainer.
**Preconditions**: The team wants more than one external automated reviewer for
the same review phase.

**Steps**:

1. The maintainer reads the advanced multi-bot guidance.
2. The maintainer reviews the expected cost, latency, and reviewer-conflict
   risks.
3. The maintainer configures multiple external reviewers intentionally.
4. The maintainer treats any non-blocking configuration warning as advisory.

**Postconditions**: The multi-bot configuration remains supported, and the
maintainer understands that it is an advanced operating mode.

**Information shown**:

- Multi-bot usage is advanced, not the default recommendation.
- Added reviewers can increase review latency and reviewer noise.
- Conflicting reviewer advice may require explicit disposition.

**Actions available**:

- Keep the multi-bot setup.
- Reduce the configuration to one external reviewer.
- Document a local rationale for the advanced setup.

**Considerations**:

- Any warning about multiple external reviewers must be non-blocking.
- The warning should point maintainers to the documented trade-offs.

## Business Rules

- The recommended default is one external automated reviewer per repository or
  product, paired with the runner's internal review gate.
- Multi-bot external review remains supported as an advanced configuration.
- Documentation must explain the main multi-bot trade-offs: cost, latency,
  duplicated findings, and conflicting reviewer advice.
- Any validator warning for multiple external reviewers must be advisory and
  must not fail workflow configuration validation by itself.
- Existing repositories with multi-reviewer configurations must continue to
  validate unless they have another blocking configuration error.

## Operational Visibility

- **Documentation guidance**: External review documentation states the
  recommended pattern and advanced multi-bot trade-offs.
- **Configuration feedback**: If implemented, the validator warning identifies
  the phase that has multiple external reviewers and names the recommendation as
  advisory.

## Acceptance Criteria

- [ ] AC-1: External review documentation recommends one external reviewer per
      repository or product plus internal runner review as the default pattern.
- [ ] AC-2: Documentation describes multi-bot external review as advanced usage
      and names cost, latency, duplicated findings, and conflict trade-offs.
- [ ] AC-3: Repository-mode or related configuration guidance points
      maintainers to the same recommended pattern without contradicting the
      external review documentation.
- [ ] AC-4: If the workflow configuration validator emits a warning for more
      than one external reviewer in a phase, the warning is non-blocking and
      does not fail otherwise valid configuration.
- [ ] AC-5: Existing multi-reviewer configurations remain supported.

## Coverage Matrix

| Brief objective | Coverage |
| --------------- | -------- |
| Update external review documentation with the recommended one-external-reviewer pattern plus internal runner reviewers. | AC-1, AC-3 |
| Document multi-bot as advanced usage with cost, latency, and conflict trade-offs. | AC-2, AC-5 |
| Optionally warn when more than one external reviewer is listed per phase. | AC-4, AC-5 |

## Out of Scope (MVP)

- Removing support for multiple external reviewers.
- Choosing a specific external reviewer provider for downstream repositories.
- Changing reviewer merge authority, readiness labels, or delegated merge gates.
