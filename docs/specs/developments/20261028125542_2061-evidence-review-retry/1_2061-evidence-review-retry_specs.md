# Evidence review retry — Spec

## Overview

Maintainers must be able to satisfy a review finding by publishing missing verification evidence and requesting a fresh review without changing otherwise correct code. Evidence findings remain pending until a reviewer verifies the new evidence. This corrects the reviewer loop described in issue #2061 without weakening code review or existing execution limits.

The approved scope covers local review evidence access, explicit retry on the same commit, and PR-Agent's treatment of requests for human verification. Human alignment selected reviewer verification of new evidence before clearance; publication alone does not grant approval.

## Use Cases

### Use Case 1: Resolve an evidence finding without a new commit

**Actor**: Maintainer or an agent authorized to address review findings.
**Preconditions**: A pull request has an open finding about missing evidence; its code has not changed.

**Steps**:

1. Publish the requested proof in the pull request body or a pull request comment.
2. Explicitly request another review of the same commit.
3. The reviewer reads the published evidence and determines whether it satisfies the finding.

**Postconditions**: Sufficient evidence can clear the finding through a fresh review, without an artificial commit or human intervention to unlock the retry. Insufficient evidence leaves the finding pending.

**Information shown**: The reviewed commit, review outcome, and the reason any finding remains pending.

**Actions available**: Publish corrected evidence and request another bounded retry, or address an actual code finding in code.

**Considerations**: Publication is not approval. Code findings, unavailable evidence, unknown results, and a changed commit must not be treated as verified evidence.

### Use Case 2: Handle PR-Agent verification requests

**Actor**: Maintainer running the configured reviewer loop.
**Preconditions**: PR-Agent's ticket analysis requests further human verification.

**Steps**:

1. Publish the relevant verification evidence in the pull request.
2. Have a reviewer verify that evidence for the current commit and the outstanding request.
3. Run the loop and readiness checks against that verified evidence.

**Postconditions**: The wording of a verification request alone does not force human escalation after its evidence has been verified. Unresolved code findings and genuinely ambiguous or unverified requests continue to prevent readiness.

**Information shown**: Whether verification is outstanding, verified, or unavailable, and any remaining blocker.

**Actions available**: Supply missing proof, request verification, or seek human resolution for a genuinely unresolved request.

**Considerations**: A statement that verification was performed, or an unrelated review approval, cannot substitute for verification of the requested proof.

## Business Rules

- Evidence findings and code findings retain their different remedies: proof may satisfy the former; the latter require correction or an existing authorized disposition.
- Findings remain pending until a reviewer verifies the supplied proof. The implementation may retain existing finding severity while allowing evidence to satisfy it.
- Reviewers receive the pull request body and published comments as evidence context. Documentation identifies both supported publication locations and the retry procedure.
- Explicit retry permits a real fresh review of the same commit after an evidence finding. It never grants a clean result by itself, erases prior review history, or resets existing cycle limits.
- Reviewer conclusions must apply to the current commit and to the evidence actually reviewed. A commit or relevant evidence change cannot inherit verification of an older revision.
- Missing, unreadable, malformed, or incomplete evidence cannot satisfy a finding. Report the unavailable or unresolved condition through the existing workflow outcomes.
- Published content is material to assess, not authority to bypass review instructions or gates. Existing protections for code findings, human change requests, merge authority, and security decisions remain in force.
- The loop and readiness checker agree on whether PR-Agent verification remains outstanding.

## Review Decision Matrix

Apply rows in order. A more restrictive existing code, security, or human blocker takes precedence over evidence clearance.

| Inputs | Allowed outcome | Required next action | Affected surfaces / example |
| --- | --- | --- | --- |
| Outstanding code finding or human blocker, regardless of evidence publication | Existing blocking outcome | Correct or resolve the blocker through existing policy | Reviewer loop and readiness; proof cannot clear a code defect |
| Unknown or unavailable review/evidence, including malformed inputs | Existing unavailable, pending, or escalation outcome as appropriate | Obtain readable evidence and a determinate review; never infer approval | Context collection, reviewer loop, readiness |
| Retry requested after the commit changes | No same-commit verification carryover | Review the new commit through existing gates | Retry identity and reviewer evidence |
| Retry would exceed an existing execution limit | Existing limit outcome | Follow existing escalation policy | Loop history and cycle limits |
| Evidence finding; missing proof or proof published without fresh verification | Pending finding | Explicitly retry review, including on the same commit | Local reviewer and retry handling; add a planted-violation proof in a comment |
| Evidence finding; fresh reviewer verifies proof for the current commit and relevant evidence | Finding may be cleared | Continue all remaining configured review and readiness gates | Local reviewer, loop history, readiness |
| Evidence finding; fresh reviewer rejects proof | Pending finding | Improve proof or correct the underlying defect; retain history and limits | Local reviewer and retry handling |
| PR-Agent requests verification; matching evidence verified for the current commit and relevant evidence | Phrase alone does not cause escalation | Continue other checks; any independent blocker still applies | PR-Agent classifier, loop, readiness |
| PR-Agent requests verification; no matching current verification | Existing unresolved outcome | Obtain verification or resolve ambiguity | PR-Agent classifier, loop, readiness |

Within the unavailable row, preserve the existing distinction between waiting for a reviewer and a terminal review failure; neither permits readiness. Repeated retries retain their prior history and cannot create an unbounded loop.

## Operational Visibility

- Existing review summaries identify the reviewed commit and outcome; pending evidence and unavailable verification remain visible.
- Retry history preserves the previous failure and the fresh review outcome rather than rewriting the failed review into an approval.
- Existing output contracts remain authoritative; exact representation and binding of evidence are implementation-plan decisions.

## Acceptance Criteria

- [ ] AC1: A synthetic pull request whose sole finding is missing verification proof can publish sufficient proof in its body or a comment, explicitly retry on the same commit, receive fresh reviewer verification, and pass the loop without an artificial commit or a human unlock.
- [ ] AC2: Publishing proof without reviewer verification, or publishing insufficient proof, leaves the finding pending. A code finding remains blocking despite evidence-only clearance elsewhere.
- [ ] AC3: The local reviewer can read published body and comment evidence; unavailable or incomplete context cannot falsely clear a finding. Operator documentation describes supported locations and the retry procedure.
- [ ] AC4: Same-commit retry performs a real review, preserves prior history and execution limits, checks commit identity, and does not reuse verification after the relevant evidence or commit changes.
- [ ] AC5: PR-Agent's verification wording alone does not escalate after matching evidence is verified for the current commit and relevant evidence. The loop and readiness agree; unverified, malformed, genuinely ambiguous, and independently blocking reviews remain blocked.
- [ ] AC6: Synthetic regression tests demonstrate both successful evidence resolution and rejection of missing, insufficient, stale, unrelated, or unavailable evidence, code blockers, changed commits, and exhausted retry limits. No downstream repository or private configuration is used as test data.

## Brief Objective List and Coverage

| Brief objective | Coverage |
| --- | --- |
| Distinguish evidence remedies from code fixes | Business rules; AC1, AC2 |
| Let reviewers see published evidence and document its location | Use Case 1; AC3 |
| Permit retry on the same commit after evidence changes | Use Case 1; AC1, AC4 |
| Avoid PR-Agent escalation solely for a satisfied verification request | Use Case 2; AC5 |
| Demonstrate completion without an artificial commit or human unlock | AC1; AC6 |

No brief objective is deferred.

## Out of Scope (MVP)

- Automatic approval merely because evidence is posted, weakening required verification, or suppressing code findings.
- Changing review providers, introducing a new architecture, or changing merge/checkpoint authority.
- Resetting review history, removing cycle limits, or modifying unrelated reviewer classifications.
- Repairing the downstream pull requests cited in the issue or using their data in tests.
- UI changes, design assets, and product analytics; this change concerns the existing command workflow.
