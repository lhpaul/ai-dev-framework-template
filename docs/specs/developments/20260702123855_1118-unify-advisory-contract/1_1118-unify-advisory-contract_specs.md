# Unified Advisory Contract - Spec

**Epic**: #1112 External review loop - Haystack advisory hardening
**Depends on**: #1113 Structured Haystack Advisory Findings

---

## Overview

Workflow maintainers need one provider-agnostic advisory finding contract across
automated review platforms. Today, PR-Agent and Haystack expose advisory signal
with different names and shapes, which makes summary rendering, disposition
tracking, and downstream adapters harder to keep consistent.

This feature defines one normalized advisory findings list for reviewer-loop
consumers while preserving existing platform-specific compatibility signals for
one transition release. Review summaries and delegated merge audit inputs should
be able to consume the unified advisory list without knowing which provider
produced each finding.

## Brief Objective List

Derived from issue #1118:

1. Define a provider-agnostic `ADVISORY_FINDINGS` contract in the generic PR
   review platform documentation.
2. Ensure PR-Agent and Haystack reviewer wrappers emit the unified contract,
   while PR-Agent may keep `ADVISORY_LABELS` as a deprecated compatibility alias
   for one release.
3. Ensure `pr-review-loop.sh` aggregates advisories from all platforms into the
   reviewer-loop summary and disposition input.
4. Update Protocol 93 to reference the unified advisory contract.

## Use Cases

### Use Case 1: Maintainer reviews advisory findings across platforms

**Actor**: Workflow maintainer.
**Preconditions**: A pull request has completed automated review and at least
one configured reviewer reported a non-blocking advisory.

**Steps**:

1. The maintainer opens the reviewer-loop summary comment.
2. The maintainer reads the advisory findings list.
3. The maintainer sees each advisory's source platform, category, summary, and
   available context.
4. The maintainer records a fix or accept disposition for each advisory.

**Postconditions**: Advisory review is recorded consistently regardless of
which platform produced the finding.

**Information shown**:

- Advisory source platform.
- Advisory category and summary.
- Optional detail, location, fix hint, and disposition metadata when available.

**Actions available**:

- Fix an advisory.
- Accept an advisory with rationale.
- Use the same review workflow for PR-Agent, Haystack, and future platforms.

**Considerations**:

- Compatibility aliases must not create duplicate human-facing advisory rows.
- Missing optional advisory fields should not hide the finding.

### Use Case 2: Downstream adapter consumes one advisory list

**Actor**: Adapter maintainer or workflow integrator.
**Preconditions**: A downstream workflow adapter reads reviewer-loop output.

**Steps**:

1. The adapter reads the unified advisory findings output.
2. The adapter parses one provider-agnostic structure.
3. The adapter maps entries into its own review disposition or reporting model.

**Postconditions**: The adapter no longer needs provider-specific handling for
PR-Agent advisory labels versus Haystack structured advisory JSON.

**Information shown**:

- One normalized advisory list with stable fields.
- Provider identity for platform-specific debugging.
- Deprecated alias information only as a compatibility aid.

**Actions available**:

- Consume the unified list.
- Ignore deprecated compatibility aliases.
- Add support for future review platforms by emitting the same contract.

**Considerations**:

- The unified contract should be easy to validate in shell tests.
- Existing users of PR-Agent advisory labels need a transition window.

## Business Rules

- `ADVISORY_FINDINGS` is the canonical advisory contract for automated reviewer
  loop consumers.
- Each advisory finding must identify its source platform.
- Each advisory finding must include a category and summary when the provider
  exposes them; missing optional detail or location fields must not drop the
  finding.
- PR-Agent may keep `ADVISORY_LABELS` for one release as a deprecated alias.
- Haystack structured advisory output must be mapped into the same advisory
  list without losing known false-positive disposition metadata.
- The reviewer-loop summary must render advisory findings from the unified list.
- Advisory disposition input must be derivable from the unified list without
  provider-specific parsing by the caller.
- The unified advisory contract must remain non-blocking by itself; blocking
  findings continue to use the existing blocking review path.

## Operational Visibility

- **Reviewer-loop summary**: Shows unified advisory findings with source,
  category, summary, optional location, and optional disposition metadata.
- **Reviewer-loop output**: Exposes a machine-readable advisory findings signal
  for downstream adapters.
- **Protocol guidance**: Protocol 93 references the unified contract as the
  source of truth for advisory disposition handling.

## Acceptance Criteria

- [ ] AC-1: Generic PR review platform documentation defines the
      provider-agnostic `ADVISORY_FINDINGS` contract, including required and
      optional fields.
- [ ] AC-2: PR-Agent wrapper output emits the unified advisory contract for
      advisory-only findings and keeps `ADVISORY_LABELS` as a documented
      deprecated alias for one release.
- [ ] AC-3: Haystack wrapper output emits or maps its structured advisory
      findings into the unified advisory contract without losing category,
      summary, detail, location, fix hint, or known false-positive disposition
      metadata when those fields are available.
- [ ] AC-4: `pr-review-loop.sh` aggregates advisory findings from all configured
      platforms into the summary comment using the unified contract.
- [ ] AC-5: Advisory disposition input can be generated from the unified list
      without provider-specific parsing by the caller.
- [ ] AC-6: Protocol 93 references the unified advisory contract for advisory
      discovery, summary rendering, and disposition handling.
- [ ] AC-7: Existing blocking reviewer behavior and advisory-only clean exits
      continue to work.

## Coverage Matrix

| Brief objective | Coverage |
| --------------- | -------- |
| Define provider-agnostic `ADVISORY_FINDINGS` contract in `pr-review-platform.md`. | AC-1 |
| PR-Agent and Haystack wrappers emit the unified contract while retaining PR-Agent alias compatibility. | AC-2, AC-3, AC-7 |
| `pr-review-loop.sh` aggregates advisories into summary and disposition input. | AC-4, AC-5 |
| Protocol 93 references the unified contract. | AC-6 |

## Out of Scope (MVP)

- Removing `ADVISORY_LABELS` in this release.
- Changing blocking-finding classification rules.
- Adding a new external review platform.
- Changing delegated merge authority or risk policy.
