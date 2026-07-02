# Structured Haystack Advisory Findings - Spec

**Epic**: #1112 External review loop - Haystack advisory hardening

---

## Overview

Workflow operators need Haystack review results to expose the actual advisory
findings, not only a count. This feature defines a structured finding contract
for Haystack reviewer output so review summaries, delegated run audit evidence,
and downstream review adapters can show each advisory or blocking finding with
enough context to decide whether to fix, accept, or defer it.

The outcome is a richer review signal that preserves current readiness behavior:
blocking findings still stop a pull request, advisory findings remain
non-blocking, and unavailable reviewers still degrade according to existing
review-loop policy.

## Brief Objective List

Derived from issue #1113:

1. Emit structured advisory output from the Haystack reviewer with category,
   summary, detail, and optional location or fix guidance per finding.
2. Emit blocking findings in the same structured form when they are available.
3. Cover multi-advisory payloads with focused Haystack reviewer tests.
4. Document the structured finding contract in the Haystack triage guide.

## Use Cases

### Use Case 1: Review loop summarizes Haystack advisories

**Actor**: Workflow operator running `/run-reviewer-loop`, `/run-item`, or
`/run-epic`.
**Preconditions**: A pull request is open, Haystack review is configured, and
Haystack returns one or more advisory findings.

**Steps**:

1. The operator runs the normal review loop for the pull request.
2. The Haystack reviewer completes and classifies findings.
3. The reviewer output includes a structured list of each advisory finding.
4. The review loop can display the advisory count and the individual advisory
   summaries in its reviewer-loop summary.
5. The operator can decide whether each advisory should be fixed or accepted
   without rerunning Haystack manually for basic context.

**Postconditions**: The pull request remains eligible to continue when only
advisory findings are present, and the advisory details are available for
summary and disposition workflows.

**Information shown**:

- Total advisory count.
- One entry per advisory with category, summary, detail, and optional location
  or fix guidance when Haystack supplied it.
- Existing review-loop result and readiness status.

**Actions available**:

- Fix an advisory and rerun the review loop.
- Accept an advisory with rationale in the delegated disposition record.
- Continue the pull request when no blocking finding is present.

**Considerations**:

- Advisory findings must not become blocking only because they are now listed
  individually.
- Missing optional location or fix guidance must not make the structured output
  invalid when Haystack did not provide that information.

### Use Case 2: Delegated run records advisory dispositions

**Actor**: `/run-epic` or another delegated workflow runner preparing audit
evidence for an in-scope pull request.
**Preconditions**: The pull request has completed Haystack review with one or
more advisory findings and delegated review authority is active.

**Steps**:

1. The delegated runner reads the latest Haystack reviewer output.
2. The runner receives the same structured advisory list used by the review-loop
   summary.
3. The runner evaluates each advisory individually.
4. The runner records one disposition per advisory in the PR audit evidence.

**Postconditions**: The audit trail can explain which advisories were fixed,
which were accepted, and why.

**Information shown**:

- Reviewed pull request head.
- One advisory disposition entry per finding.
- Rationale for any accepted advisory.

**Actions available**:

- Apply deterministic fixes for material advisories.
- Accept low-value advisories with explicit rationale.
- Stop for human input when an advisory raises risk beyond the invocation
  policy.

**Considerations**:

- The structured finding contract should make it difficult to collapse several
  advisories into one vague disposition entry.

### Use Case 3: Blocking findings share the same finding shape

**Actor**: Workflow operator responding to a Haystack review that found blocking
issues.
**Preconditions**: Haystack returns one or more blocking findings.

**Steps**:

1. The Haystack reviewer classifies findings by severity.
2. Blocking findings are emitted as individual structured entries when their
   details are available.
3. The review loop stops the pull request as needing fixes.
4. The operator can inspect the blocking findings in the same shape as advisory
   findings.

**Postconditions**: The pull request is blocked as before, but downstream
summary and audit consumers can use one finding model for blocking and advisory
results.

**Information shown**:

- Total blocking count.
- One entry per blocking finding with category, summary, detail, and optional
  location or fix guidance when available.
- Existing needs-fixes result.

**Actions available**:

- Fix blocking findings and rerun the review loop.
- Escalate if the finding cannot be interpreted from the available details.

**Considerations**:

- The existing blocking behavior is preserved; the structured data is an
  additional contract for consumers.

## Business Rules

- The Haystack reviewer must continue to emit the existing review result,
  blocking count, advisory count, and total comment count used by the current
  review loop.
- When Haystack returns advisory findings, each advisory must be represented as
  a discrete structured finding.
- Structured advisory findings must include at least a category, summary, and
  detail. Location and fix guidance are optional because Haystack may not supply
  them for every finding.
- Blocking findings should use the same structured finding shape when source
  data is available.
- Advisory-only review output must remain non-blocking for readiness decisions.
- Reviewer-unavailable behavior must remain unchanged when Haystack cannot run
  or cannot return parseable review data.
- Structured finding output must be machine-readable by scripts and still
  understandable enough for humans reading logs or PR summaries.
- The structured contract must be documented so downstream repositories and
  review adapters can consume it without inspecting the reviewer implementation.

## Statuses / Enum Values

No workflow statuses are introduced. The feature preserves the existing review
result values:

| Result value  | Display label | Description |
| ------------- | ------------- | ----------- |
| `clean`       | Clean         | No blocking findings were found; advisory findings may still be present. |
| `needs_fixes` | Needs fixes   | One or more blocking findings require changes before readiness. |
| `skipped`     | Skipped       | Haystack was unavailable or not applicable according to review policy. |
| `escalate`    | Escalate      | The reviewer could not produce a reliable result and human attention is needed. |

Structured findings use this severity display model:

| Severity value | Display label | Description |
| -------------- | ------------- | ----------- |
| `blocking`     | Blocking      | The finding prevents readiness until fixed or escalated. |
| `advisory`     | Advisory      | The finding is non-blocking but should be fixed or accepted with rationale. |

## Operational Visibility

- **Reviewer-loop summary**: Can show individual Haystack advisories instead of
  only a total count.
- **Script output**: Exposes structured finding data alongside the existing
  review-loop key-value summary.
- **Logs**: Preserve enough raw or normalized finding detail for troubleshooting
  parser issues.
- **Audit trail**: Delegated runners can record one advisory disposition per
  structured finding.
- **Documentation**: The Haystack triage guide identifies the fields consumers
  can rely on and which fields are optional.

## Acceptance Criteria

- [ ] AC-1: When Haystack returns multiple advisory findings, the reviewer emits
      a machine-readable list containing one structured entry per advisory.
- [ ] AC-2: Each structured advisory entry includes category, summary, and
      detail, and includes location or fix guidance when Haystack supplies it.
- [ ] AC-3: When Haystack returns blocking findings with parseable details, the
      reviewer emits those findings using the same structured finding shape as
      advisories.
- [ ] AC-4: The existing review result, blocking count, advisory count, and total
      comment count remain available to existing review-loop consumers.
- [ ] AC-5: Advisory-only Haystack results continue to allow the review loop to
      advance without setting a blocking needs-fixes state.
- [ ] AC-6: Focused Haystack reviewer tests cover a payload with multiple
      advisory findings and verify that each finding is preserved separately.
- [ ] AC-7: The Haystack triage guide documents the structured finding contract,
      including required fields, optional fields, and how blocking and advisory
      findings are represented.

## Coverage Matrix

| Brief objective | Covered by |
| --------------- | ---------- |
| Emit structured advisory output with category, summary, detail, and optional location or fix guidance per finding. | AC-1, AC-2 |
| Emit blocking findings in the same structured form when available. | AC-3 |
| Cover multi-advisory payloads with focused tests. | AC-6 |
| Document the structured finding contract in the Haystack triage guide. | AC-7 |

## Out of Scope (MVP)

- Changing Haystack's own review categories, severities, or source output.
- Making advisory findings blocking by policy.
- Replacing the existing review-loop result and count fields.
- Implementing the later cross-platform advisory aggregation contract for
  PR-Agent and future reviewers.
- Creating a machine-readable false-positive catalog.
- Changing the delegated merge gate beyond giving it richer advisory evidence.
