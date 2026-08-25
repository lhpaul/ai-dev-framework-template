# Repo-Native Automated PR Reviewer Spike/MVP - Spec

## Overview

Workflow operators need a faster, cheaper first review pass for routine pull requests before the existing ready-phase Codex GitHub review runs. This spike/MVP defines a local-only CLI reviewer that lives in the repository workflow, produces auditable review evidence, and helps reduce repeated external review rounds without replacing the ready-phase `codex-github` gate.

The MVP is intentionally scoped to local command-line review and design validation. Graph-assisted context tools may be evaluated as inputs, but they are not mandatory unless the spike proves that they materially improve review quality or cost.

---

## Use Cases

### Run local CLI review before ready-phase validation

**Actor**: Workflow operator.
**Preconditions**: A pull request is in the workflow review path and the repository has enabled the local reviewer option for the relevant stage.

**Steps**:

1. The workflow starts the local CLI reviewer for the current pull request.
2. The local reviewer inspects the pull request diff, the repository review contract, and the bounded context selected for the changed surface.
3. The local reviewer reports whether the pull request is clean, needs fixes, or cannot produce review evidence.
4. The workflow records the result in the same review-loop evidence stream used by other automated reviewers.
5. If the local reviewer is clean or intentionally skipped, the workflow may continue to the configured ready-phase reviewers.

**Postconditions**: The pull request has a current local-review disposition that is distinct from ready-phase Codex GitHub evidence.

**Information shown**:

- Local reviewer name.
- Reviewed pull request and head commit.
- Clean, needs-fixes, skipped, unavailable, malformed, or timeout disposition.
- Blocking and advisory counts when findings are present.
- A concise summary of what context was reviewed.

**Actions available**:

- Continue the reviewer loop when the result is clean or intentionally skipped.
- Return the pull request for fixes when blocking findings are present.
- Escalate to an operator when the local reviewer cannot produce reliable evidence.

**Considerations**:

- A local reviewer result never counts as Codex GitHub evidence.
- A skipped or unavailable local review is availability evidence, not clean review evidence.
- The ready-phase `codex-github` reviewer remains configured so operators can measure whether it still finds net-new blockers.

### Evaluate graph-assisted context selection

**Actor**: Workflow maintainer.
**Preconditions**: The spike is comparing local review context strategies.

**Steps**:

1. The maintainer selects representative pull requests or existing changesets.
2. The spike compares local review with no graph context against local review with candidate graph-assisted context.
3. The spike records whether graph context improves signal, reduces review effort, or creates operational complexity.
4. The spike recommends whether graph-assisted context is required for MVP, optional, or deferred.

**Postconditions**: The implementation path names the default MVP context strategy and any optional graph integration boundary.

**Information shown**:

- Candidate context strategy.
- Setup requirements.
- Review signal observed.
- Latency or effort impact.
- Recommended adoption decision.

**Actions available**:

- Proceed with a no-graph MVP.
- Add optional graph context support.
- Defer graph tooling until a later item.

**Considerations**:

- Graph tooling must not become a mandatory dependency before the spike proves value.
- Candidate tools are context routers, not authoritative reviewers.
- Any graph-backed result must still be normalized into the repository review-loop contract.

### Preserve ready-phase Codex GitHub validation

**Actor**: Workflow operator.
**Preconditions**: The local reviewer has completed or been intentionally skipped and the pull request reaches ready-phase validation.

**Steps**:

1. The workflow keeps `codex-github` in the ready-phase reviewer list.
2. The workflow runs ready-phase validation using the existing reviewer-loop rules.
3. The workflow records whether Codex GitHub finds net-new blockers after local review.
4. Operators use that evidence to decide whether future defaults should keep, demote, or conditionally run Codex GitHub.

**Postconditions**: The workflow can measure review-round reduction without weakening current ready-phase validation.

**Information shown**:

- Local reviewer disposition.
- Codex GitHub disposition.
- Whether Codex GitHub reported net-new blocking findings after local review.
- Any timeout or unavailable state tied to the current head.

**Actions available**:

- Keep both reviewers configured.
- Adjust local-review findings and retry.
- Later propose a separate policy change if measured evidence supports it.

**Considerations**:

- Codex GitHub timeout, usage-limit, or setup failure remains unavailable evidence and must not be treated as clean.
- Replacement or conditional execution of Codex GitHub is out of scope for this MVP.

---

## Business Rules

- The first deliverable is a spike/MVP design, not the full reviewer subsystem.
- The MVP reviewer is local-only CLI review; native GitHub inline comments are deferred.
- The reviewer must fit the existing automated reviewer contract: clean, needs-fixes, skipped, unavailable, malformed, timeout, or escalation states remain distinguishable.
- `codex-github` remains in the ready-phase during rollout and measurement.
- The local reviewer may reduce external review rounds, but it does not replace human review, merge approval, CI, or current-head ready-phase evidence.
- Graph-assisted tools may help select context, but the repository-owned reviewer remains responsible for the final normalized disposition.
- Missing local tools, authentication, model access, malformed output, or timeout are not clean review evidence.
- Blocking findings from the local reviewer keep the pull request out of ready-for-human-review until fixed or explicitly escalated.

---

## Operational Visibility

- **Logs**: The review loop records the local reviewer platform name, result, reason, counts, reviewed head, and context source summary.
- **Notifications**: Pull request review summaries distinguish local review findings from Codex GitHub findings.
- **Audit trail**: The PR keeps enough evidence to compare local-review outcome against later Codex GitHub outcome for the same head.

---

## Acceptance Criteria

- [ ] A workflow maintainer can read the spike/MVP design and understand the local-only CLI reviewer boundary.
- [ ] The design explains how the local reviewer fits the existing automated reviewer result contract.
- [ ] The design preserves `codex-github` as ready-phase validation and explains how to measure net-new Codex findings.
- [ ] The design identifies deterministic checks that should run before any LLM-backed review pass.
- [ ] The design classifies graph-assisted context as required, optional, or deferred based on spike evidence.
- [ ] The design defines unavailable, skipped, timeout, malformed-output, clean, and needs-fixes behavior without treating availability failures as clean review evidence.
- [ ] The design calls out follow-up implementation work separately from the spike/MVP scope.

---

## Out of Scope (MVP)

- Replacing or removing ready-phase `codex-github`.
- Posting local reviewer findings as native GitHub inline review comments.
- Building or hosting a SaaS reviewer.
- Making graph tooling mandatory before the spike proves value.
- Granting merge authority to the local reviewer.
- Changing human review requirements or CI readiness rules.

---

## Brief Objective List

1. Compare a no-graph baseline, `code-review-graph`, and `graphify` for local PR-review context selection.
2. Define the expected local reviewer platform contract for the existing review loop.
3. Identify deterministic checks that should run before any LLM review pass.
4. Propose timeout, unavailable, malformed-output, and finding-classification behavior.
5. Preserve `codex-github` in ready phase and measure whether it finds fewer net-new blockers after local review.
6. Keep the MVP local-only CLI review, with GitHub inline comments deferred.

## Coverage Matrix

| Brief objective | Coverage |
| --- | --- |
| Compare context strategies | Use case "Evaluate graph-assisted context selection"; AC5 |
| Define review-loop platform contract | Use case "Run local CLI review before ready-phase validation"; AC2, AC6 |
| Identify deterministic pre-review checks | Business Rules; AC4 |
| Propose failure and finding behavior | Business Rules; AC6 |
| Preserve and measure Codex GitHub | Use case "Preserve ready-phase Codex GitHub validation"; AC3 |
| Keep local-only CLI MVP | Overview; Business Rules; AC1, AC7 |

## Complex Workflow Decision Matrix

| Reviewer outcome | Workflow result | Required next action | Mirror surfaces | Example |
| --- | --- | --- | --- | --- |
| Clean local review | Continue | Proceed to the next configured reviewer stage, including ready-phase `codex-github` when applicable. | Review-loop output, PR summary, stage handoff | The local reviewer reports no blocking findings for the current head. |
| Blocking local findings | Needs fixes | Return the pull request for fixes and rerun review after a push. | Review-loop output, fixer handoff, PR summary | The local reviewer finds an uncovered workflow-contract edge case. |
| Advisory local findings | Continue with visible advisories | Keep suggestions non-blocking unless restated as blocking by the review contract. | Review-loop output, PR summary | The reviewer suggests clearer documentation wording. |
| Skipped by configuration | Skipped | Continue only as an intentional skipped reviewer, not as clean local review evidence. | Review-loop output, PR summary | The local reviewer is disabled in a downstream repository. |
| Missing local dependency or access | Unavailable or skipped with reason | Surface the reason and follow the configured reviewer-loop policy. | Review-loop output, operator summary | The local LLM command is not installed or authenticated. |
| Timeout | Escalate or unavailable with reason | Stop or continue according to explicit policy, without claiming clean review. | Review-loop output, operator summary | The local review exceeds its allowed runtime. |
| Malformed output | Escalate | Treat the result as unreliable and require operator action or a retry. | Review-loop output, operator summary | The local reviewer emits text that cannot be parsed into the required result contract. |
| Codex GitHub net-new blocker after local clean | Needs fixes | Fix the branch and rerun the configured review loop. | Ready-phase review evidence, PR summary | Codex GitHub catches a workflow edge case missed by local review. |
