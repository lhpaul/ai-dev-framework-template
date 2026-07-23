# Access-Restricted Reviewer Checks at the Merge Gate — Spec

---

## Overview

This feature lets the AI development workflow distinguish a third-party
reviewer check that cannot complete because of repository or organization access
restrictions from a genuine code-review finding or failing CI. The workflow
prioritizes restoring reviewer access and exposes a protection-bypass option
only to a human who explicitly authorizes it for the named pull request. Any
authorized bypass remains evidence-based, visible, and auditable.

## Brief Objective List

- **OBJ-1**: Detect and report reviewer access restrictions separately from
  genuine blocking findings and failing CI.
- **OBJ-2**: Recommend repository or organization App-access remediation as the
  primary path.
- **OBJ-3**: Present a human-only escalation option, with exact required
  evidence, when access restriction is the only remaining blocker.
- **OBJ-4**: Never execute a protection bypass without explicit human
  authorization for the named pull request.
- **OBJ-5**: Record the authorization, CI state, reviewer disposition, blocked
  check, and bypass reason in the pull request audit trail.
- **OBJ-6**: Document an organization-access preflight for Haystack setup.

## Use Cases

### Use Case 1: Diagnose a non-green reviewer check

**Actor**: Workflow operator

**Preconditions**: A pull request has reached its merge gate and a configured
third-party reviewer check is failing or remains pending.

**Steps**:

1. The operator asks the workflow to evaluate why the pull request cannot
   merge.
2. The workflow compares required CI results, the reviewer's latest
   disposition, the non-green check, and available access-restriction evidence.
3. The workflow classifies the situation as an access restriction, a genuine
   review or CI blocker, or insufficient evidence.
4. The workflow presents the classification, supporting evidence, and required
   next action.

**Postconditions**: The operator can distinguish reviewer infrastructure access
from code quality and CI health without treating one as evidence for another.

**Information shown**:

- Required CI results for the current pull request revision
- Latest reviewer disposition and blocking-finding count
- Name and state of the blocked reviewer check
- Access-restriction evidence, when available
- Classification and next action

**Actions available**:

- Remediate repository or organization App access
- Retry the reviewer check after remediation
- Fix genuine review or CI failures
- Request a human-only escalation when all eligibility rules are satisfied

**Considerations**:

- A non-green reviewer check alone is not proof of an access restriction.
- Missing or contradictory evidence results in an insufficient-evidence outcome,
  not an automatic bypass recommendation.

### Use Case 2: Restore reviewer access

**Actor**: Repository or organization administrator

**Preconditions**: The workflow has classified the only reviewer failure as an
access restriction.

**Steps**:

1. The workflow identifies repository or organization App access as the primary
   remediation.
2. The administrator grants or corrects the required access.
3. The operator retries the reviewer check.
4. The workflow evaluates the refreshed reviewer and CI state.

**Postconditions**: The normal protected merge path resumes when reviewer access
is restored and all required checks pass.

**Information shown**:

- Reviewer or App that lacks access
- Repository or organization level at which access should be verified
- Instruction to retry and re-evaluate current evidence

**Actions available**:

- Open the relevant repository or organization App-access settings
- Retry the reviewer
- Return to the normal merge gate

**Considerations**:

- The workflow does not grant permissions on the administrator's behalf.
- Restoring access does not waive later review findings or CI failures.

### Use Case 3: Authorize an exceptional protection bypass

**Actor**: Human merge authorizer

**Preconditions**: Required CI is green for the current pull request revision,
the reviewer reports no blocking findings, the only remaining blocker is a
verified access-restricted reviewer check, and access remediation cannot unblock
the pull request in the required timeframe.

**Steps**:

1. The workflow presents the named pull request and the complete eligibility
   evidence.
2. The workflow explains that the normal remediation remains preferred and
   identifies the exceptional protection-bypass action.
3. The human explicitly approves or rejects the bypass for that pull request.
4. If approved, the workflow records the authorization and evidence before the
   bypass is attempted.
5. The workflow performs only the specifically authorized merge action and
   reports its result.

**Postconditions**: The merge is either not attempted, rejected, or completed
under explicit human authorization with a durable audit record.

**Information shown**:

- Pull request number and current revision
- Required CI state
- Reviewer disposition and blocking-finding count
- Blocked check and access-restriction evidence
- Proposed `gh pr merge <pull-request> --admin` action and reason
- Audit record status

**Actions available**:

- Approve the bypass for the named pull request
- Reject the bypass
- Return to App-access remediation
- Stop and investigate contradictory or stale evidence

**Considerations**:

- Delegated or autonomous merge authority does not substitute for explicit
  human authorization.
- Authorization must be renewed if the pull request revision or material gate
  evidence changes before the merge attempt.
- A bypass is never offered for failing CI or genuine blocking review findings.

### Use Case 4: Preflight Haystack organization access

**Actor**: Workflow integrator

**Preconditions**: Haystack is being enabled for a repository owned by an
organization that may restrict third-party GitHub Apps.

**Steps**:

1. The integrator follows the Haystack setup guidance.
2. The guidance prompts the integrator to verify organization approval and
   repository access before relying on the reviewer check.
3. The integrator confirms access or obtains the required administrator
   approval.
4. The integrator verifies that a test pull request can produce a usable
   reviewer result.

**Postconditions**: Access restrictions are discovered during setup instead of
   appearing later as an unexplained merge-gate failure.

**Information shown**:

- Where organization and repository App access must be verified
- Expected successful reviewer signal
- Troubleshooting direction for an access-restricted response

**Actions available**:

- Request organization approval
- Grant repository access
- Validate the integration on a test pull request

**Considerations**:

- Setup guidance must not imply that local CLI authentication proves GitHub App
  access.

## Business Rules

- **BR-1**: The workflow classifies a reviewer check as access-restricted only
  when all required CI checks are green for the current pull request revision,
  the reviewer reports zero blocking findings, the reviewer check remains
  non-green, and available evidence identifies an access denial such as HTTP
  403 or an equivalent provider response.
- **BR-2**: Any failing or incomplete required CI check produces a genuine CI
  blocker outcome, regardless of reviewer access evidence.
- **BR-3**: Any blocking reviewer finding produces a genuine review blocker
  outcome, regardless of check-run access evidence.
- **BR-4**: Missing, stale, or contradictory evidence produces an
  insufficient-evidence outcome and requires human investigation.
- **BR-5**: Restoring repository or organization App access is always the
  primary recommendation for a verified access restriction.
- **BR-6**: The exceptional protection-bypass option is shown only when the
  access-restricted reviewer check is the sole remaining merge blocker.
- **BR-7**: No workflow mode, delegated merge permission, risk classification,
  or prior approval authorizes a protection bypass. Explicit human authorization
  must name the pull request.
- **BR-8**: Authorization applies only to the presented pull request revision
  and evidence. A revision change or material gate-state change invalidates it.
- **BR-9**: The audit trail must exist before a bypass attempt and must include
  the human authorization, pull request and revision, CI state, reviewer
  disposition, blocked check, access-restriction evidence, bypass reason, and
  final result.
- **BR-10**: The pending implementation-stage security checkpoint remains in
  force: a human must review the security-sensitive implementation approach
  before delegated merge of the future implementation pull request.
- **BR-11**: Setup guidance distinguishes GitHub App repository or organization
  access from local reviewer-tool installation and authentication.

## Decision-Gate Consistency Matrix

| Gate inputs | Allowed outcome | Required next action | Mirror surfaces | Example |
| --- | --- | --- | --- | --- |
| Required CI is failing or incomplete | Genuine CI blocker | Fix or complete CI; do not offer a bypass | Merge/readiness protocol, operator summary, audit evidence | A production build fails while the reviewer check also returns 403 |
| Reviewer has one or more blocking findings | Genuine review blocker | Address findings and rerun review; do not offer a bypass | Reviewer loop, merge/readiness protocol, operator summary | Reviewer reports a logic error and its check is non-green |
| Required CI is green, reviewer has zero blockers, and verified access-denial evidence exists | Access restriction | Recommend App-access remediation and retry | Merge/readiness protocol, reviewer integration guidance, operator summary | Haystack analysis is clear but its check cannot read the repository because organization approval is missing |
| Access restriction is verified but remediation has not been attempted or remains available | Remediation required | Restore repository or organization access | Integration setup guide, operator summary | Repository was not selected in the App installation |
| Access restriction is the only blocker and remediation cannot unblock in time, but no human authorization exists | Human authorization required | Present evidence and wait; do not execute a bypass | Merge/readiness protocol, audit trail, operator summary | Release is blocked by an organization approval delay |
| Eligible evidence exists and a human explicitly authorizes the named pull request and revision | Exceptional bypass authorized | Write audit evidence, then attempt only the authorized merge | Merge/readiness protocol, audit trail, operator summary | Human approves the named pull request after reviewing green CI and zero reviewer blockers |
| Evidence is missing, stale, or contradictory | Insufficient evidence | Stop for human investigation and refresh evidence | Merge/readiness protocol, operator summary | Reviewer comment is for an older revision than the check run |

## Operational Visibility

- **Operator report**: Shows the classification, current-revision evidence, and
  required next action without collapsing reviewer health into CI health.
- **Setup guidance**: Provides an organization-access preflight and
  troubleshooting path for Haystack.
- **Audit trail**: Records every exceptional bypass decision and attempt on the
  affected pull request, including rejected or failed attempts.
- **Checkpoint visibility**: The implementation plan and implementation pull
  request must surface the pending security checkpoint until a human satisfies
  it.

## Acceptance Criteria

- [ ] **AC-1**: Given green required CI, zero reviewer blocking findings, a
  non-green third-party reviewer check, and verified access-denial evidence, the
  workflow reports an access restriction separately from review and CI
  failures.
- [ ] **AC-2**: Given any failing or incomplete required CI check, the workflow
  reports a CI blocker and does not present a protection-bypass option.
- [ ] **AC-3**: Given any blocking reviewer finding, the workflow reports a
  review blocker and does not present a protection-bypass option.
- [ ] **AC-4**: Given missing, stale, or contradictory evidence, the workflow
  reports insufficient evidence and requests human investigation instead of
  guessing.
- [ ] **AC-5**: A verified access restriction presents repository or
  organization App-access remediation as the primary next action.
- [ ] **AC-6**: When an access-restricted reviewer check is the only blocker,
  the workflow shows the exact evidence required for a human-only exceptional
  bypass decision and presents `gh pr merge <pull-request> --admin` as the
  sanctioned action without executing it.
- [ ] **AC-7**: Without explicit human authorization naming the pull request,
  no workflow path executes or represents itself as authorized to execute a
  protection bypass.
- [ ] **AC-8**: Authorization captured for one pull request revision is rejected
  after the revision or material gate evidence changes until a human
  reauthorizes it.
- [ ] **AC-9**: Before an authorized bypass attempt, the pull request audit trail
  contains the authorization, revision, CI state, reviewer disposition, blocked
  check, access-restriction evidence, and bypass reason; afterward it records
  the result.
- [ ] **AC-10**: Delegated or autonomous merge authority without the additional
  named human authorization cannot satisfy the bypass gate.
- [ ] **AC-11**: Haystack integration guidance includes an organization and
  repository App-access preflight, the expected successful signal, and
  troubleshooting for access-restricted responses.
- [ ] **AC-12**: The future implementation handoff retains a pending
  security-sensitive checkpoint requiring human review before delegated merge.
- [ ] **AC-13**: Each decision-gate input combination in the consistency matrix
  yields the same outcome and next action across the merge/readiness protocol,
  reviewer integration guidance, operator summary, and audit evidence.

## Coverage Matrix

| Brief objective | Coverage |
| --- | --- |
| OBJ-1: Distinguish access restriction from genuine findings and failing CI | BR-1 through BR-4; AC-1 through AC-4 |
| OBJ-2: Prefer App-access remediation | Use Case 2; BR-5; AC-5 |
| OBJ-3: Present an evidence-based human-only escalation | Use Case 3; BR-6; AC-6 |
| OBJ-4: Require explicit authorization for the named pull request | BR-7 and BR-8; AC-7, AC-8, and AC-10 |
| OBJ-5: Record authorization and merge-gate evidence | BR-9; Operational Visibility; AC-9 |
| OBJ-6: Add the Haystack organization-access preflight | Use Case 4; BR-11; AC-11 |

## Out of Scope (MVP)

- Automatically changing repository or organization GitHub App permissions.
- Automatically authorizing a protection bypass in any workflow mode.
- Bypassing genuine CI failures, blocking reviewer findings, unresolved review
  threads, or unrelated branch-protection requirements.
- Changing repository branch-protection rules.
- Generalizing every reviewer outage or service failure into an access
  restriction without provider evidence.
- Defining the implementation mechanism, command structure, or files that
  enforce the gate; those decisions belong in the implementation plan.
