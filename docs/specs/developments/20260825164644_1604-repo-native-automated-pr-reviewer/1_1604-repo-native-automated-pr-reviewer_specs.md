# Repo-Native Automated PR Reviewer Spike/MVP - Spec

## Overview

Workflow operators need a faster, cheaper first review pass for routine pull requests before the existing ready-phase Codex GitHub review runs. This spike/MVP defines a local-only CLI reviewer that lives in the repository workflow, produces auditable review evidence, and helps reduce repeated external review rounds without replacing the ready-phase `codex-github` gate.

The MVP is intentionally scoped to local command-line review and design validation. Graph-assisted context tools may be evaluated as inputs, but they are not mandatory unless the spike proves that they materially improve review quality or cost.

The local reviewer lifecycle bucket is the automated PR reviewer loop, not the internal Step 7a runner gate. It is expected to behave like other `pr-review-loop.sh` platforms and emit normalized result evidence before ready-phase reviewers run.

---

## Use Cases

### Run local CLI review before ready-phase validation

**Actor**: Workflow operator.
**Preconditions**: A pull request is in the workflow review path and the repository has enabled the local reviewer as a `pr-review-loop.sh` platform.

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
- The local reviewer belongs in the `pr-review-loop.sh` platform lifecycle, such as a draft-phase platform that runs after internal Step 7a approval and before ready-phase `codex-github`.
- The local reviewer is not a `review.on_draft.runner` internal reviewer and does not replace the stage-specific native review gate.
- The reviewer must fit the existing automated reviewer contract: clean, needs-fixes, skipped, unavailable, malformed, timeout, or escalation states remain distinguishable.
- `codex-github` remains in the ready-phase during rollout and measurement.
- The local reviewer may reduce external review rounds, but it does not replace human review, merge approval, CI, or current-head ready-phase evidence.
- Graph-assisted tools may help select context, but the repository-owned reviewer remains responsible for the final normalized disposition.
- Missing local tools, authentication, model access, malformed output, or timeout are not clean review evidence.
- Blocking findings from the local reviewer keep the pull request out of ready-for-human-review until fixed or explicitly escalated.

---

## Deterministic Pre-Review Checks

The spike/MVP design must define these deterministic checks before any LLM-backed review pass:

- **Current-head binding**: confirm the reviewed checkout, pull request metadata, and emitted result all refer to the same pull request head commit.
- **Diff scope**: list changed files and classify the PR stage from branch name and changed artifact paths.
- **Stage artifact boundary**: verify spec branches contain only spec-stage artifacts, plan branches contain only plan-stage artifacts, and implementation branches do not silently mix documentation-stage artifacts.
- **Review contract loading**: confirm `REVIEW.md` and the applicable stage checklist are available before local review starts.
- **Placeholder and stale-marker scan**: run the stage-appropriate placeholder, TODO, FIXME, debug-comment, and review-marker checks before LLM review.
- **Validation evidence scan**: collect relevant local validation commands already run or required by the stage so the LLM reviewer can flag missing evidence instead of guessing.
- **Unresolved-thread scan**: identify existing unresolved blocking reviewer threads before claiming a clean local review.
- **Failure-state classification**: classify missing tools, missing credentials, timeout, and malformed result separately before any result is normalized.

These checks are the MVP floor. The implementation plan may add more checks, but it must not remove these without a new human-approved scope decision.

---

## Graph Context Adoption Criteria

The spike compares three context strategies:

1. No graph: changed files, `REVIEW.md`, relevant workflow docs, and targeted `rg` context.
2. `code-review-graph`: graph-assisted impact/context selection for the same representative pull requests.
3. `graphify`: broader code/docs/config graph context for the same representative pull requests when setup is practical.

The spike must use at least three representative pull requests or historical changesets:

- One spec or plan documentation-only workflow PR.
- One workflow script or reviewer-loop change.
- One mixed documentation plus script change, or the closest available historical equivalent.

For each strategy, record:

- Setup effort: none, low, medium, or high.
- Additional context returned beyond changed files.
- Whether the context exposed a real review concern missed by the no-graph baseline.
- Whether the context created false leads or excessive noise.
- Runtime or operator effort impact, using concrete observed timings when available.

Adoption decision rules:

Evaluate the outcomes in this order so every strategy maps to exactly one category:

1. **Deferred** if graph context adds high setup effort, high noise, no material net-new review concern, or unclear operational value.
2. **Required for MVP** only if the strategy is not deferred and graph context finds at least one material review concern missed by the no-graph baseline in two or more representative inputs, with low or medium setup effort.
3. **Optional for MVP** only if the strategy is not deferred or required, and graph context improves context quality or ergonomics in at least one representative input.
4. **Deferred** if none of the above rules match.

---

## Failure Policy

The MVP default policy is fail-closed for unreliable local review results:

- Missing local reviewer command, missing model access, and missing credentials default to `escalate` with an explicit reason; they never produce `clean` or an implicit `skipped`.
- Timeout defaults to `escalate` for the local reviewer MVP because no current-head review evidence was produced.
- Malformed output defaults to `escalate` because the workflow cannot trust the reported counts or disposition.
- Missing optional graph tooling is not a local-review failure when graph context is configured as optional; the reviewer falls back to no-graph context and records `GRAPH_CONTEXT=skipped` with a reason.
- Missing mandatory graph tooling is a configuration error only if a future human-approved policy makes graph context required.
- Skipped local review is allowed only when the platform is disabled by configuration or explicitly unavailable under a documented warn-and-continue policy.
- A future warn-and-continue policy may convert a setup/access failure from `escalate` to `skipped`, but only when the policy is explicitly configured and the summary states that no fresh local review evidence was produced.

Finding normalization follows the repository review contract:

- `blocking` findings produce `needs_fixes`.
- `important` findings produce `needs_fixes` by default because the repository review contract says to fix them unless a human decision is required.
- `suggestion` findings remain advisory and allow the loop to continue unless the reviewer explicitly restates them as blocking.

The spike may propose additional policy modes, but the MVP must define the default branch for every failure class above.

---

## Operational Visibility

- **Logs**: The review loop records the local reviewer platform name, result, reason, counts, reviewed head, and context source summary.
- **Notifications**: Pull request review summaries distinguish local review findings from Codex GitHub findings.
- **Audit trail**: The PR keeps enough evidence to compare local-review outcome against later Codex GitHub outcome for the same head.

---

## Net-New Codex Finding Measurement

The rollout metric compares local reviewer findings with ready-phase Codex GitHub findings only when both were produced for the same pull request head commit.

The local reviewer must retain comparison evidence for each finding:

- Reviewed head commit.
- Severity after normalization.
- Affected file path and line or range when available.
- Short finding title.
- Stable category such as workflow-contract, missing-validation, stale-marker, docs-consistency, or unavailable-evidence.
- One-sentence finding summary.

A Codex GitHub finding is **not net-new** when it matches a local finding on the same head by either:

- The same affected path plus substantially the same requirement or failure mode, even if wording, line number, or severity differs.
- The same stable category plus the same missing or violated workflow obligation.

A Codex GitHub finding is **net-new** when no same-head local finding matches by those rules.

Ambiguous matches are counted as net-new for the metric and must be listed as ambiguous in the review summary. This keeps rollout measurement conservative and reproducible: unclear credit goes to the ready-phase reviewer, not the local reviewer.

---

## Acceptance Criteria

- [ ] A workflow maintainer can read the spike/MVP design and understand the local-only CLI reviewer boundary.
- [ ] The design explains how the local reviewer fits the existing automated reviewer result contract.
- [ ] The design preserves `codex-github` as ready-phase validation and explains how to measure net-new Codex findings.
- [ ] The design identifies deterministic checks that should run before any LLM-backed review pass.
- [ ] The design classifies graph-assisted context as required, optional, or deferred using representative inputs, recorded measurements, and explicit decision thresholds.
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

## Follow-Up Implementation Work

If the spike/MVP design is accepted, follow-up implementation should be split into separate work items or plan steps:

- Add a `local-ai-reviewer` companion script that emits the standard reviewer-loop key-value result contract.
- Add a `pr-review-loop.sh` platform adapter for `local-ai-reviewer`.
- Add deterministic pre-review checks and fixture coverage for each required failure state.
- Add configuration documentation showing the local reviewer before ready-phase `codex-github`.
- Add optional graph-context support only if the spike adoption criteria classify a graph strategy as required or optional.
- Add rollout measurement evidence that reports ready-phase Codex GitHub net-new blockers after local review.

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
| Identify deterministic pre-review checks | Deterministic Pre-Review Checks; AC4 |
| Propose failure and finding behavior | Failure Policy; Business Rules; AC6 |
| Preserve and measure Codex GitHub | Use case "Preserve ready-phase Codex GitHub validation"; AC3 |
| Keep local-only CLI MVP | Overview; Business Rules; AC1 |
| Separate follow-up implementation work | Follow-Up Implementation Work; AC7 |

## Complex Workflow Decision Matrix

| Reviewer outcome | Workflow result | Required next action | Mirror surfaces | Example |
| --- | --- | --- | --- | --- |
| Clean local review | Continue | Proceed to the next configured reviewer stage, including ready-phase `codex-github` when applicable. | Review-loop output, PR summary, stage handoff | The local reviewer reports no blocking findings for the current head. |
| Blocking local findings | Needs fixes | Return the pull request for fixes and rerun review after a push. | Review-loop output, fixer handoff, PR summary | The local reviewer finds an uncovered workflow-contract edge case. |
| Important local findings | Needs fixes | Return the pull request for fixes by default, or escalate when the finding requires a human decision. | Review-loop output, fixer handoff, PR summary | The reviewer finds an incomplete workflow update that should be fixed before readiness. |
| Suggestion local findings | Continue with visible advisories | Keep suggestions non-blocking unless restated as blocking by the review contract. | Review-loop output, PR summary | The reviewer suggests clearer documentation wording. |
| Skipped by configuration | Skipped | Continue only as an intentional skipped reviewer, not as clean local review evidence. | Review-loop output, PR summary | The local reviewer is disabled in a downstream repository. |
| Missing local dependency or access | Escalate | Stop for operator action unless a future explicit warn-and-continue policy converts the result to skipped with a no-fresh-review warning. | Review-loop output, operator summary | The local LLM command is not installed or authenticated. |
| Missing optional graph dependency | Continue with no-graph fallback | Record graph context as skipped with a reason, then continue local review using the no-graph context strategy. | Review-loop output, operator summary | `code-review-graph` is not installed while graph context is optional. |
| Timeout | Escalate | Stop for operator action or retry without claiming clean review. | Review-loop output, operator summary | The local review exceeds its allowed runtime. |
| Malformed output | Escalate | Treat the result as unreliable and require operator action or a retry. | Review-loop output, operator summary | The local reviewer emits text that cannot be parsed into the required result contract. |
| Codex GitHub net-new blocker after local clean | Needs fixes | Fix the branch and rerun the configured review loop. | Ready-phase review evidence, PR summary | Codex GitHub catches a workflow edge case missed by local review. |
