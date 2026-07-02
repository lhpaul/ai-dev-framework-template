# Machine-readable False-positive Catalog - Spec

**Epic**: #1112 External review loop - Haystack advisory hardening
**Depends on**: #1113 Structured Haystack Advisory Findings

---

## Overview

Workflow operators need recurring known false positives from external reviewers
to be recognized consistently instead of rediscovered in every run. This feature
introduces a machine-readable catalog for known Haystack false-positive patterns
so reviewer summaries and delegated audit evidence can identify matching
findings as known false positives with a visible disposition.

The outcome is a review loop that remains transparent: known false positives do
not block readiness, but they are still shown to the operator with enough
context to understand why they were classified that way and when the catalog
needs maintenance.

## Brief Objective List

Derived from issue #1115:

1. Add a machine-readable false-positive catalog with match rules for category,
   summary, and path-style reviewer evidence.
2. Mark matching Haystack findings as non-blocking known false positives in
   structured reviewer output.
3. Cross-reference Helm's false-positive documentation format where applicable.
4. Cover at least the CHANGELOG and hotfix-backport false-positive patterns with
   focused tests.

## Use Cases

### Use Case 1: Known false positive is classified during review

**Actor**: Workflow operator running `/run-reviewer-loop`, `/run-item`, or
`/run-epic`.
**Preconditions**: A pull request is under review, Haystack is configured, and a
review finding matches a cataloged false-positive pattern.

**Steps**:

1. The operator runs the normal reviewer loop for the pull request.
2. Haystack returns one or more findings.
3. The review loop compares the findings with the known false-positive catalog.
4. A matching finding remains visible in the summary and is labeled as a known
   false positive.
5. The operator can continue readiness decisions without rediscovering the same
   false-positive rationale.

**Postconditions**: The finding does not create a blocking readiness state, and
the summary records that it matched a known false-positive rule.

**Information shown**:

- The reviewer result and readiness state.
- The matched false-positive classification.
- The original finding category, summary, and available location context.
- The catalog rationale or reference that explains the match.

**Actions available**:

- Continue the review when only known false positives remain.
- Fix unrelated blocking findings and rerun the reviewer loop.
- Escalate when a finding only partially matches or the catalog rationale is no
  longer trustworthy.

**Considerations**:

- Known false-positive classification must not hide the original finding from
  summaries or audit evidence.
- A catalog match must be deterministic for the same reviewer evidence.

### Use Case 2: Delegated run records known false-positive disposition

**Actor**: `/run-epic` or another delegated workflow runner preparing PR audit
evidence.
**Preconditions**: Delegated review authority is active, and the reviewer output
contains a known false-positive match.

**Steps**:

1. The delegated runner reads the reviewer-loop result.
2. The runner sees that a finding is classified as a known false positive.
3. The runner records the classification in the PR disposition or readiness
   evidence.
4. The runner proceeds only when no unresolved blocking findings or unmatched
   advisory findings remain.

**Postconditions**: The audit trail explains why the known false positive did
not block merge readiness.

**Information shown**:

- Reviewed pull request head.
- The matched false-positive finding.
- The rule name or human-readable rationale for the match.
- Whether any non-matching findings still require action.

**Actions available**:

- Accept the known false-positive disposition when the match is clear.
- Stop for human review when the classification is ambiguous.
- Update the catalog through a separate workflow change when the known pattern
  is stale or incomplete.

**Considerations**:

- Delegated runners must not collapse several different findings into one vague
  false-positive decision.
- Matching a known false positive does not override merge risk, CI, or human
  checkpoint requirements.

### Use Case 3: Maintainer reviews catalog coverage

**Actor**: Workflow maintainer updating external-review guidance.
**Preconditions**: The repository has one or more documented known
false-positive reviewer patterns.

**Steps**:

1. The maintainer reads the machine-readable catalog and related guidance.
2. The maintainer can identify which reviewer pattern each entry covers.
3. The maintainer can compare the template catalog format with downstream
   project formats such as Helm's false-positive documentation.
4. The maintainer can add or adjust entries in a future change without changing
   the reviewer-loop contract.

**Postconditions**: Known false-positive behavior is discoverable from
repository-maintained documentation and tests.

**Information shown**:

- Catalog entry name or purpose.
- Matching dimensions used by the entry.
- Human-readable rationale or reference.
- Expected review-loop disposition.

**Actions available**:

- Add a new false-positive pattern.
- Narrow an overly broad pattern.
- Remove a stale pattern.
- Compare the template format with downstream documentation before syncing.

**Considerations**:

- Catalog entries should be narrow enough to avoid masking real findings.
- Cross-repository references should guide compatibility without making this
  template depend on one downstream repository's private files.

## Business Rules

- A reviewer finding that matches a cataloged known false-positive pattern must
  remain visible in reviewer-loop output and audit evidence.
- A matched known false positive must be non-blocking by default unless another
  policy, risk gate, or human checkpoint requires escalation.
- A known false-positive disposition must include a stable human-readable reason
  or reference.
- Catalog matching must be based on reviewer evidence that is available in the
  structured finding output, such as category, summary, detail, or path context.
- A finding that does not clearly match a catalog entry must keep its normal
  reviewer classification.
- Multiple findings must be classified independently; one known false-positive
  match must not classify unrelated findings.
- Catalog guidance must explain how the template format relates to Helm's
  false-positive documentation pattern without requiring Helm-specific files in
  this repository.

## Statuses / Enum Values

No workflow item statuses are introduced. The feature adds a disposition label
for reviewer findings:

| Disposition value | Display label | Description |
| ----------------- | ------------- | ----------- |
| `known-false-positive` | Known false positive | The finding matched a maintained false-positive rule and is non-blocking with rationale. |

The existing review-loop result labels continue to apply:

| Result value  | Display label | Description |
| ------------- | ------------- | ----------- |
| `clean`       | Clean         | No blocking findings remain; known false positives may be present in the summary. |
| `needs_fixes` | Needs fixes   | One or more blocking findings must be addressed before readiness. |
| `skipped`     | Skipped       | A reviewer did not produce a completed review result. |
| `escalate`    | Escalate      | The review loop cannot determine readiness safely. |

## Operational Visibility

- **Reviewer-loop summary**: Shows matched known false positives alongside the
  original reviewer finding context.
- **Structured reviewer output**: Preserves each finding's classification and
  known false-positive disposition for downstream audit consumers.
- **Documentation**: Explains the catalog purpose, matching dimensions, and
  relationship to Helm's false-positive documentation format.
- **Audit trail**: Delegated runs can cite known false-positive dispositions
  when explaining why a finding did not block readiness.
- **Tests**: Demonstrate that representative known false-positive patterns are
  matched and remain non-blocking.

## Acceptance Criteria

- [ ] AC-1: The repository exposes a machine-readable catalog of known
      false-positive reviewer patterns with match dimensions for category,
      summary, and path-style evidence.
- [ ] AC-2: When a Haystack finding matches a catalog entry, reviewer output
      marks that finding with a known-false-positive disposition and keeps the
      original finding visible.
- [ ] AC-3: A matched known false positive is treated as non-blocking unless a
      separate policy, risk gate, or human checkpoint requires escalation.
- [ ] AC-4: Findings that do not match the catalog keep their normal reviewer
      classification.
- [ ] AC-5: Multiple findings are evaluated independently so a catalog match for
      one finding does not change unrelated findings.
- [ ] AC-6: Documentation cross-references Helm's false-positive documentation
      format where applicable and explains any template-specific differences.
- [ ] AC-7: Focused tests cover known false-positive patterns for CHANGELOG
      findings and hotfix-backport findings.

## Coverage Matrix

| Brief objective | Covered by |
| --------------- | ---------- |
| Add a machine-readable false-positive catalog with match rules for category, summary, and path-style reviewer evidence. | AC-1 |
| Mark matching Haystack findings as non-blocking known false positives in structured reviewer output. | AC-2, AC-3, AC-4, AC-5 |
| Cross-reference Helm's false-positive documentation format where applicable. | AC-6 |
| Cover at least the CHANGELOG and hotfix-backport false-positive patterns with focused tests. | AC-7 |

## Out of Scope (MVP)

- Defining the full unified advisory contract across every review platform; that
  remains tracked by #1118.
- Moving Haystack runtime configuration into repository config; that remains
  tracked by #1116.
- Automatically generating catalog entries from reviewer output.
- Suppressing known false positives from summaries or audit evidence.
- Changing merge-risk classification, CI requirements, or human-checkpoint
  behavior.
- Requiring downstream repositories to adopt Helm's exact documentation format.
