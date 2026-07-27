# Access-Restricted Reviewer Checks at the Merge Gate — Implementation Plan

**Spec**:
[1_access-restricted-reviewer-checks_specs.md](1_access-restricted-reviewer-checks_specs.md)
**Smoke test runbook**:
[1288-access-restricted-reviewer-checks.smoke-test.md](../../../testing/workflow/1288-access-restricted-reviewer-checks.smoke-test.md)

---

## Summary

**Approach**: Extend the existing delegated merge gate and audit-trail helpers
instead of creating a second merge-authority model. The CI loop will expose a
structured snapshot of configured reviewer checks; the delegated gate will
combine that snapshot with current-revision CI, reviewer, access-denial, scope,
risk, and authorization evidence to distinguish genuine blockers,
access-restricted infrastructure, and insufficient evidence. A verified access
restriction will prefer App-access remediation and will remain non-mergeable
until a human separately authorizes the named pull request and revision and a
stable audit record exists before the exact `gh pr merge <pr> --admin` action.

**Estimated complexity**: L

**Rationale**: The implementation changes a security-sensitive merge decision
gate across single-item, explicit-batch, and epic workflows. It adds structured
evidence and audit contracts, freshness checks, shell tests, a narrowly scoped
exception to the batch merge route, and mirrored agent/skill guidance. No
product application or database layer changes.

**Dependencies**: None. The existing Haystack reviewer already emits
`REASON=forbidden`, `pr-review-loop.sh` forwards that reason, and
`pr-ci-loop.sh` already excludes configured reviewer checks from genuine CI.
Issue #1188 is prior related work but does not block implementation.

---

## Template-Fit Check

`.ai-dev-workflow.yaml` sets `template.is_template: true`. This feature changes
framework-agnostic workflow scripts, protocols, and reviewer integration
guidance used by downstream repositories regardless of their product stack.
**Pass**.

---

## Pending Implementation-Stage Security Checkpoint

The approved checkpoint policy for issue #1288 applies to the
**implementation** stage, not this Plan Ready stage. It remains **pending** and
must be carried into the future implementation handoff and implementation pull
request:

- **Domain**: security
- **Reason**: protection-bypass authorization, evidence freshness, and audit
  ordering are security-sensitive.
- **Required human action**: review the security-sensitive implementation
  approach before delegated merge of the implementation pull request.
- **Enforcement**: the future implementation PR must remain blocked by the
  normal checkpoint lifecycle until the required human review is recorded as
  satisfied. Delegated/autonomous merge authority, a generic waiver, and the
  earlier batch approval do not satisfy this checkpoint.

The plan PR must not receive `human-checkpoint-required` for this future-stage
checkpoint. The checkpoint is preserved here and in the handoff so the
implementation runner can apply it when the implementation stage becomes
current.

---

## Verification Log

| Check | Command / query | Result |
| --- | --- | --- |
| Repo revision | `git rev-parse --short HEAD` | `21f23e3` |
| Template fit | `rg -n "is_template" .ai-dev-workflow.yaml` | `template.is_template: true`; scope is generic workflow tooling |
| Approved spec | `docs/specs/developments/20260723112258_access-restricted-reviewer-checks/1_access-restricted-reviewer-checks_specs.md` | OBJ-1–OBJ-6, AC-1–AC-13, and the seven-row decision matrix are approved |
| Existing Haystack denial signal | `rg -n "HTTP 403|forbidden" scripts/development-workflow/haystack-reviewer.sh scripts/development-workflow/tests/test-haystack-reviewer.sh` | `haystack-reviewer.sh` maps HTTP 403 to `REASON=forbidden`; automated coverage already exists |
| Reviewer reason propagation | `rg -n "forbidden|unauthorized" scripts/development-workflow/pr-review-loop.sh` | Reviewer-loop history and aggregate output preserve `forbidden` / `unauthorized` as infrastructure reasons |
| CI/reviewer separation | `rg -n "REVIEWER_CHECK" scripts/development-workflow/pr-ci-loop.sh scripts/development-workflow/tests/test-workflow-orchestration-product-repo-aware.sh` | CI loop ignores configured reviewer checks for CI health but currently reports only count/name, not the structured state needed by the merge gate |
| Delegated merge surfaces | `rg -l "run-epic-delegated-gate\\.sh|merge_allowed" docs/workflow/development-workflow/protocols docs/workflow/development-workflow/guardrails-enforcement.md .agents/skills .codex/skills .claude/agents .cursor/agents` | 16 canonical/mirrored files currently describe the normal gate or `merge_allowed` path |
| Audit surfaces | `rg -l "run-epic-audit-trail\\.sh|pr-disposition" docs/workflow/development-workflow/protocols docs/workflow/development-workflow/guardrails-enforcement.md .agents/skills .codex/skills .claude/agents .cursor/agents scripts/development-workflow/tests` | Six existing audit references; `run-epic-audit-trail.sh` owns stable PR disposition comments |
| Batch merge route | `rg -n 'batch-merge\\.sh|Direct .*gh pr merge|gh pr merge' docs/workflow/development-workflow/protocols/90-batch-orchestrate-work-protocol.md docs/workflow/development-workflow/protocols/94-batch-merge-protocol.md .agents/skills/run-items/SKILL.md` | Parallel implementation batches normally prohibit direct `gh pr merge`; the exceptional human-authorized path needs an explicit, narrow exception |
| Design assets | Issue body, tracker data, linked files, and `<dev-folder>/assets/` | No UI scope or design assets; fidelity steps are not applicable |

---

## Classifier Results

| Classifier | Applies? | Rationale |
| --- | --- | --- |
| Parser-risk | **Yes** | `pr-ci-loop.sh`, `run-epic-delegated-gate.sh`, and `run-epic-audit-trail.sh` parse and emit structured JSON/key-value evidence and stable Markdown audit records |
| Concurrent-event-source | No | Polling is sequential; no new listeners, queues, timers sharing mutable state, or teardown lifecycle are introduced |
| Cross-cutting checklist | No | The feature changes a specific merge decision gate; it does not add or rename a planning/review checklist category applied to independent features |
| Complex workflow decision-gate | **Yes** | Outcomes depend on CI, reviewer disposition, reviewer check state, access evidence, freshness, authorization, audit state, scope/risk, and merge route across mirrored workflows |
| Output/API contract | **Yes** | The CI loop gains additive structured reviewer-check output, and the delegated gate gains additive evidence/result fields and exceptional outcomes |
| Single-snapshot consistency | **Yes** | Authorization is valid only for one pull request revision and one canonical material-evidence fingerprint |

---

## Architecture Decisions

### AD-1: Reuse the delegated gate as the only merge-policy path

`scripts/development-workflow/run-epic-delegated-gate.sh` remains the read-only
authority that classifies a merge candidate. The helper name is historical, but
Protocol 91 and `/run-items` already reuse it outside epic runs. The
implementation must extend this helper rather than introduce a second policy or
an autonomous `--admin` merge helper.

Normal candidates retain the existing `merge_allowed`, `fix_required`,
`human_required`, and `blocked` behavior. The new access-restriction branch is
additive and must never turn a non-green reviewer check into normal
`merge_allowed`.

### AD-2: Preserve raw reviewer-check state as structured evidence

`pr-ci-loop.sh` will continue to exclude configured reviewer checks from
`TOTAL_CHECK_COUNT`, `FAILING_CHECKS`, and the CI `RESULT`. Add
`REVIEWER_CHECKS_JSON=<compact-json>` using `jq -c`, alongside the legacy
fields. The JSON array preserves, per current check:

- check name and provider/configured reviewer identity;
- status/state and conclusion;
- details URL when GitHub supplies one;
- check timestamp and pull request head SHA used for the observation.

Keep existing `REVIEWER_CHECK_COUNT` and `REVIEWER_CHECKS` fields unchanged for
backward compatibility. The structured field is evidence for the delegated
merge gate; it is not reclassified as generic CI.

### AD-3: Canonical material-evidence fingerprint

For the access-restriction branch, the delegated gate will canonicalize and
fingerprint only the material facts that authorization covers:

- pull request number, repository, and current head SHA;
- required CI names/states for that SHA;
- reviewer result/reason and blocking count for that SHA;
- blocked reviewer check name/state;
- provider access-denial signal and source;
- remediation-attempt state, why access cannot be restored in the required
  timeframe, and the operator-provided bypass reason;
- mergeability/base-currency facts needed to establish that the reviewer check
  is the only remaining protection blocker.

Use `jq -cS` for deterministic key ordering and the repository's existing
OpenSSL dependency (`openssl dgst -sha256`) for the fingerprint. The gate
returns the computed fingerprint in its read-only result. Authorization must
name the PR, head SHA, and fingerprint. Any head change or material evidence
change produces `insufficient_evidence` / renewed authorization required; no
substring, timestamp-only, or stale-comment matching may preserve
authorization.

### AD-4: Separate classification from exceptional authorization

The delegated gate will expose a structured `reviewerAccess` result with a
classification, evidence deficiencies, remediation, and bypass eligibility.
Canonical classifications:

- `not_applicable`
- `ci_blocker`
- `review_blocker`
- `access_restricted`
- `insufficient_evidence`
- `authorization_required`
- `authorization_stale`
- `audit_required`
- `exceptional_bypass_authorized`

The assembled evidence object uses these additive fields:

- `reviewerChecks`: decoded current array from `REVIEWER_CHECKS_JSON`;
- `reviewer.headSha`, `reviewer.status`, `reviewer.reason`, and
  `reviewer.blockingCount`;
- `accessRestriction.provider`, `accessRestriction.reason`,
  `accessRestriction.source`, `accessRestriction.evidence`,
  `accessRestriction.headSha`, `accessRestriction.remediationAttempted`,
  `accessRestriction.cannotUnblockInTime`, and
  `accessRestriction.bypassReason`;
- `authorization.pullRequest`, `authorization.headSha`,
  `authorization.evidenceFingerprint`, `authorization.authorizedBy`,
  `authorization.authorizedAt`, and `authorization.authorizationText`;
- `bypassAudit.present`, `bypassAudit.state`,
  `bypassAudit.evidenceFingerprint`, and `bypassAudit.commentId`.

Eligibility for the human authorization prompt requires
`remediationAttempted=true`, `cannotUnblockInTime=true`, and a non-empty
`bypassReason`. Otherwise the classification remains `access_restricted` with
remediation required.

`exceptional_bypass_authorized` is not normal delegated `merge_allowed`. It is
reachable only when the access-restricted reviewer check is the sole remaining
blocker, a direct human authorization names the current PR/SHA/fingerprint, and
the pre-attempt audit marker is present. The result must clearly state that only
the named `gh pr merge <pr> --admin` action is authorized. A policy boolean,
batch confirmation, `mayMerge`, `delegateReview`, risk threshold, or satisfied
unrelated checkpoint is never substituted for that authorization.

GitHub may report `mergeStateStatus=BLOCKED` solely because the required
reviewer check is non-green. The exceptional branch may accept that value only
when `mergeable=MERGEABLE`, the branch is current with its approved base, and
every other Gate 5 condition passes. `DIRTY`, `UNKNOWN`, behind-base state, an
unresolved review decision/thread, another non-green required check, or any
unexplained protection blocker yields `insufficient_evidence` or the applicable
genuine blocker. The normal `merge_allowed` path continues to require its
existing clean merge state.

Top-level decision mapping stays explicit and backward compatible:

- `ci_blocker` / `review_blocker` → existing `fix_required`;
- `access_restricted`, `authorization_required`, `authorization_stale`, or
  `audit_required` → existing `human_required`;
- `insufficient_evidence` → existing `blocked`;
- fully eligible, current, authorized, and audited evidence →
  `exceptional_bypass_authorized`;
- unaffected normal candidates retain the existing `merge_allowed` path.

### AD-5: Two-phase stable audit comment

Extend `run-epic-audit-trail.sh` with stable render/apply operations for an
access-restricted reviewer bypass record:
`render-reviewer-access-bypass --input <file>` and
`apply-reviewer-access-bypass --input <file> --pr <number>`. Use the exact
marker `<!-- reviewer-access-bypass -->` and update it rather than posting
duplicate comments.

Before an attempted bypass, the record must contain:

- human identity or durable authorizer label supplied by the runner;
- authorization text/timestamp;
- PR number, repository, head SHA, and material-evidence fingerprint;
- required CI evidence;
- reviewer disposition and blocking count;
- blocked check and access-denial evidence;
- remediation status and reason remediation cannot unblock in time;
- exact proposed `gh pr merge <pr> --admin` action;
- state `authorized_pending_attempt`.

After rejection or an attempt, update the same marker with `rejected`,
`merged`, or `failed`, plus the command result and live PR state. Redaction
rules from the existing audit helper continue to apply. The protocol must
verify the pre-attempt marker exists before running the command and must update
the final result even when the merge command fails.

### AD-6: The human-only command stays outside helpers

No script added or modified by this feature may autonomously invoke
`gh pr merge --admin`. After the gate returns
`exceptional_bypass_authorized` and the pre-attempt audit is verified, the
runner executes the exact named command once, then performs existing merge
verification, branch cleanup, tracker reconciliation, and final audit update.
This keeps explicit human authorization visible at the action boundary and
prevents a generic retry/fallback helper from escalating privileges.

### AD-7: Narrow batch-route exception

Protocol 94 remains the normal route for parallel implementation PRs. If one PR
has a verified access-restricted reviewer check:

1. keep all other PRs on the normal batch route;
2. refresh the named PR against the current base and rerun reviewer/CI evidence
   so it is mergeable and current;
3. present a separate named PR/SHA/fingerprint authorization prompt—prior batch
   approval is insufficient;
4. record and verify the pre-attempt audit;
5. execute only the authorized admin merge for that named PR;
6. fetch the new base, verify `MERGED`, run cleanup/tracker reconciliation, and
   resume the remaining sequential batch from fresh discovery.

This exception does not authorize direct merging of unaffected batch PRs and
does not bypass CHANGELOG conflict resolution, unresolved threads, genuine
review findings, CI, risk, or checkpoint gates.

---

## Decision-Gate Consistency Matrix

| Gate inputs | Allowed outcome | Required next action | Mirror surfaces | Example |
| --- | --- | --- | --- | --- |
| Any required CI failing, pending, missing, or stale | `ci_blocker` / existing `fix_required` | Fix or complete CI; do not show an admin option | Delegated gate, Protocols 90/91/95, operator summary, audit | Production build fails while Haystack also returns 403 |
| Reviewer has a blocking finding or unresolved blocking thread | `review_blocker` / existing `fix_required` | Fix findings and rerun review; do not show an admin option | Delegated gate, reviewer loop, Protocols 90/91/95 | Haystack reports a logic error and its check is non-green |
| CI green, zero blockers, configured reviewer check non-green, current verified denial signal | `access_restricted` | Recommend repository/organization App access remediation and retry | Delegated gate, Haystack guide, operator summary | Haystack CLI returns `REASON=forbidden` for the current head |
| Access restriction verified; remediation not attempted or still viable | `access_restricted` with remediation required | Restore App access; rerun reviewer and gate | Protocols 90/91/94/95, Haystack guide | Repository was omitted from App installation |
| Access restriction is sole blocker; remediation was attempted and cannot unblock in time; no named current authorization | `authorization_required` / `human_required` | Show PR/SHA/evidence/fingerprint, bypass reason, and exact command; wait | Delegated gate, all runner mirrors, audit | Release timing cannot wait for org approval |
| Authorization names another PR/SHA/fingerprint or evidence changes | `authorization_stale` / `insufficient_evidence` | Refresh evidence and obtain new authorization | Delegated gate, operator summary, audit | A commit is pushed after approval |
| Current named authorization exists but pre-attempt audit is absent | `audit_required` | Write and verify stable audit marker; do not merge | Delegated gate, audit helper, Protocols 91/94/95 | Human approves, but comment write fails |
| Current named authorization and pre-attempt audit exist; no other blocker | `exceptional_bypass_authorized` | Execute exactly the named admin merge once; verify and update audit | Delegated gate, Protocols 90/91/94/95, runner mirrors | Human approves PR #42 at SHA `abc…` |
| Evidence missing, contradictory, unparseable, or not current | `insufficient_evidence` | Stop for investigation; refresh evidence | Delegated gate, operator summary | Reviewer comment refers to an older SHA |
| Human rejects the presented bypass | `rejected` audit disposition | Record rejection; return to remediation or stop | Audit helper, operator summary | Authorizer declines protection bypass |

---

## Layer-by-Layer Changes

### Merge Evidence and Gate Scripts

- [ ] Update `scripts/development-workflow/pr-ci-loop.sh` to preserve current
      structured configured-reviewer check evidence while leaving existing CI
      result semantics and legacy key-value fields unchanged (AC-1, AC-2).
- [ ] Extend `scripts/development-workflow/run-epic-delegated-gate.sh` with the
      AD-3 evidence fingerprint and AD-4 classification. Preserve existing
      normal gate results and read-only guarantee (AC-1–AC-8, AC-10, AC-13).
- [ ] Extend `scripts/development-workflow/run-epic-audit-trail.sh` with
      render/apply operations for the stable two-phase bypass marker. Require
      all BR-9 fields and reject malformed/incomplete input before comment
      mutation (AC-9).
- [ ] Do not add any script path that invokes `gh pr merge --admin`. Protocol
      agents execute it only after the named human authorization and verified
      pre-attempt audit (AC-7, AC-10).

### Protocols and Merge Routing

- [ ] Update
      `docs/workflow/development-workflow/guardrails-enforcement.md` Gate 5 and
      named-stop contract. Define access restriction as an exceptional
      human-only branch after normal evidence gates, not a new guardrails
      policy or delegated authority (AC-1–AC-10).
- [ ] Update
      `docs/workflow/development-workflow/protocols/91-orchestrate-work-protocol.md`
      so single-item runners assemble current evidence, prefer remediation,
      present the exact human prompt, audit before action, perform one
      authorized command, and re-enter normal verification/cleanup (AC-1–AC-10,
      AC-13).
- [ ] Update
      `docs/workflow/development-workflow/protocols/95-run-epic-protocol.md`
      with the same gate and per-PR authorization semantics. Epic policy and
      `--may-merge` never authorize an admin bypass (AC-7, AC-10, AC-13).
- [ ] Update
      `docs/workflow/development-workflow/protocols/90-batch-orchestrate-work-protocol.md`
      so each affected PR receives a separate authorization and disposition;
      unaffected PRs remain on normal batch merge (AC-6–AC-10, AC-13).
- [ ] Update
      `docs/workflow/development-workflow/protocols/94-batch-merge-protocol.md`
      with AD-7's narrow exception, fresh-base requirement, sequential
      rediscovery, and explicit statement that batch-plan approval is not
      protection-bypass authorization (AC-6–AC-10, AC-13).

### Agent and Skill Mirrors

- [ ] Mirror the single-item gate branch in:
      - `.agents/skills/run-item/SKILL.md`
      - `.agents/skills/run-item/agents/openai.yaml`
      - `.codex/skills/workflow-item-orchestrator/SKILL.md`
      - `.codex/skills/workflow-item-orchestrator/agents/openai.yaml`
      - `.claude/agents/item-orchestrator.md`
      - `.cursor/agents/item-orchestrator.md`
- [ ] Mirror explicit-batch behavior in:
      - `.agents/skills/run-items/SKILL.md`
      - `.agents/skills/run-items/agents/openai.yaml`
      - `.codex/skills/workflow-orchestrator/SKILL.md`
      - `.codex/skills/workflow-orchestrator/agents/openai.yaml`
      - `.claude/agents/orchestrator.md`
      - `.cursor/agents/orchestrator.md`
- [ ] Mirror epic behavior in:
      - `.agents/skills/run-epic/SKILL.md`
      - `.agents/skills/run-epic/agents/openai.yaml`

Each mirror may delegate detail to the canonical protocol, but must state the
non-substitution rule: delegated/batch/epic authorization never substitutes
for a fresh named human authorization to run `--admin` (AC-7, AC-10, AC-13).

### Reviewer Integration Guidance

- [ ] Update
      `docs/workflow/development-workflow/integrations/haystack-triage.md` with:
      organization approval and repository selection preflight; distinction
      between local CLI auth and GitHub App access; expected usable reviewer
      signal on a test PR; HTTP 403 / `REASON=forbidden` troubleshooting;
      remediation-first merge-gate behavior (AC-5, AC-11).
- [ ] Review
      `docs/workflow/development-workflow/integrations/haystack.md` and add one
      cross-reference from its setup path to the canonical organization-access
      preflight. Do not duplicate the detailed instructions.
- [ ] Update `docs/workflow/development-workflow/README.md` with a concise
      high-level statement that verified reviewer access restrictions use the
      remediation-first, human-only exceptional gate. Link to the canonical
      guardrails/integration guidance instead of duplicating the full matrix.

### Tests

- [ ] Extend
      `scripts/development-workflow/tests/test-workflow-orchestration-product-repo-aware.sh`
      to assert structured reviewer-check evidence for default/custom names,
      non-green state, details URL, and unchanged genuine-CI behavior.
- [ ] Extend
      `scripts/development-workflow/tests/test-run-epic-delegated-gate.sh` with
      every decision matrix row, fingerprint/freshness checks, normal-result
      regression tests, and proof the helper never invokes mutating `gh`
      commands.
- [ ] Extend
      `scripts/development-workflow/tests/test-run-epic-audit-trail.sh` for
      required fields, authorization/rejection/attempt results, redaction,
      stable-marker create/update behavior, and comment API failures.
- [ ] Run the existing
      `scripts/development-workflow/tests/test-haystack-reviewer.sh` coverage
      for HTTP 403 → `REASON=forbidden`; no edit is planned because the
      provider-level denial signal already satisfies the new gate input.
- [ ] Run shellcheck and the workflow shell guard for every changed shell
      script.

### Database, Product API, UI, and Infrastructure

- [ ] None. No schema, seed, application runtime, UI, deployment, permission,
      or branch-protection configuration changes are in scope.

---

## Files to Modify

### Runtime and tests

| File | Change |
| --- | --- |
| `scripts/development-workflow/pr-ci-loop.sh` | Add backward-compatible structured reviewer-check snapshot output |
| `scripts/development-workflow/run-epic-delegated-gate.sh` | Add access-restriction classification, fingerprint, freshness, authorization, and audit gate |
| `scripts/development-workflow/run-epic-audit-trail.sh` | Add stable two-phase access-bypass audit record |
| `scripts/development-workflow/tests/test-workflow-orchestration-product-repo-aware.sh` | Verify structured reviewer-check output and CI separation |
| `scripts/development-workflow/tests/test-run-epic-delegated-gate.sh` | Cover decision matrix and fail-closed edge cases |
| `scripts/development-workflow/tests/test-run-epic-audit-trail.sh` | Cover required audit fields, marker lifecycle, and failures |

### Canonical workflow documentation

| File | Change |
| --- | --- |
| `docs/workflow/development-workflow/guardrails-enforcement.md` | Define exceptional access-restriction branch inside existing Gate 5 |
| `docs/workflow/development-workflow/protocols/90-batch-orchestrate-work-protocol.md` | Add per-PR batch authorization and routing |
| `docs/workflow/development-workflow/protocols/91-orchestrate-work-protocol.md` | Add single-item evidence, authorization, audit, action, and verification sequence |
| `docs/workflow/development-workflow/protocols/94-batch-merge-protocol.md` | Add narrow admin-route exception and rediscovery |
| `docs/workflow/development-workflow/protocols/95-run-epic-protocol.md` | Add per-child exceptional gate path |
| `docs/workflow/development-workflow/integrations/haystack-triage.md` | Add organization/repository App-access preflight and 403 troubleshooting |
| `docs/workflow/development-workflow/integrations/haystack.md` | Cross-reference the canonical organization-access preflight |
| `docs/workflow/development-workflow/README.md` | Summarize and link the remediation-first human-only exception |

### Agent and skill mirrors

| File | Change |
| --- | --- |
| `.agents/skills/run-item/SKILL.md` | Single-item human-only access-restriction branch |
| `.agents/skills/run-item/agents/openai.yaml` | Reinforce non-substitution rule in default prompt |
| `.agents/skills/run-items/SKILL.md` | Explicit-batch per-PR exceptional branch |
| `.agents/skills/run-items/agents/openai.yaml` | Reinforce separate named authorization |
| `.agents/skills/run-epic/SKILL.md` | Epic per-child exceptional branch |
| `.agents/skills/run-epic/agents/openai.yaml` | Reinforce separate named authorization |
| `.codex/skills/workflow-item-orchestrator/SKILL.md` | Single-item canonical wrapper behavior |
| `.codex/skills/workflow-item-orchestrator/agents/openai.yaml` | Reinforce human-only admin action |
| `.codex/skills/workflow-orchestrator/SKILL.md` | Batch canonical wrapper behavior |
| `.codex/skills/workflow-orchestrator/agents/openai.yaml` | Reinforce per-PR authorization and route |
| `.claude/agents/item-orchestrator.md` | Single-item mirror |
| `.cursor/agents/item-orchestrator.md` | Single-item mirror |
| `.claude/agents/orchestrator.md` | Batch/epic orchestration mirror |
| `.cursor/agents/orchestrator.md` | Batch/epic orchestration mirror |

### Stage artifacts

| File | Change |
| --- | --- |
| `docs/testing/workflow/1288-access-restricted-reviewer-checks.smoke-test.md` | Plan-stage runbook, executed during implementation |
| `CHANGELOG.md` | Add implementation-stage Unreleased entry; do not edit on this plan branch |

---

## Parser-Risk Edge Cases and Unit-Test Mapping

### Edge-case enumeration

| Case | Concrete input | Expected behavior |
| --- | --- | --- |
| Boundary reviewer name | `Haystack / Review` and configured `Custom Haystack Review` | Exact configured name is preserved; lookalike checks are not silently treated as the reviewer |
| Negative denial lookalike | Reviewer text contains “403 tests passed” but reason is not `forbidden` / verified provider denial | `insufficient_evidence`; no bypass option |
| Multiple checks with same key | Historical failure plus newer success for the same reviewer check | Latest current-revision check wins using existing normalization; stale duplicate is ignored |
| Multiple reviewer checks | One access-restricted reviewer and one separate failing reviewer | Access restriction is not the sole blocker; do not authorize bypass |
| CI and denial overlap | Unit Tests `FAILURE`; Haystack `FAILURE`; reviewer reason `forbidden` | `ci_blocker` takes precedence |
| Review finding and denial overlap | Blocking count `1`; reviewer reason `forbidden` | `review_blocker` takes precedence |
| Missing access source | Non-green reviewer check and zero blockers, but no 403/equivalent denial evidence | `insufficient_evidence` |
| Contradictory evidence | Reviewer result says clean but blocking count is `2` | Fail closed as review blocker/contradictory evidence |
| Head boundary | Authorization PR matches but approved SHA differs by one character | `authorization_stale`; never prefix-match |
| Fingerprint boundary | Same SHA but a CI/reviewer/check material field changes | Fingerprint mismatch; require new authorization |
| Multiple occurrences in audit text | Authorization/reason contains pipes, tabs, newlines, or repeated token-looking strings | Stable Markdown remains valid and secrets/paths are redacted |
| Nested structured values | Missing arrays, null objects, snake/camel legacy fields, malformed JSON | Preserve documented legacy aliases where already supported; otherwise fail closed with explicit reason |
| Normative syntax flexibility | GitHub CheckRun `status/conclusion` versus commit-status `state` | Normalize both existing shapes without accepting unknown states as success |
| Suppression semantics | Not applicable | No inline suppression directive is introduced |

### Unit-test mapping

- `scripts/development-workflow/tests/test-workflow-orchestration-product-repo-aware.sh`
  covers reviewer-name boundaries, latest duplicate selection, CheckRun/state
  shapes, and multiple reviewer checks in the CI output contract.
- `scripts/development-workflow/tests/test-run-epic-delegated-gate.sh` covers
  negative lookalikes, CI/review precedence, missing/contradictory evidence,
  multiple blockers, exact SHA matching, material-fingerprint invalidation,
  null/malformed shapes, and unchanged normal gate outcomes.
- `scripts/development-workflow/tests/test-run-epic-audit-trail.sh` covers
  repeated/special characters, redaction, missing required fields, and stable
  marker update behavior.
- `scripts/development-workflow/tests/test-haystack-reviewer.sh` retains the
  provider-level HTTP 403 → `REASON=forbidden` canary.

---

## Output Contract and Snapshot-Safety Checklist

- **Backward compatibility**: existing CI and delegated-gate fields retain their
  names and meanings for normal paths. New fields are additive.
- **Unknown values**: unknown, missing, or unparsable check/reviewer/access
  values never normalize to success or access-restricted eligibility.
- **Current revision**: every material evidence source must name or be fetched
  for the same head SHA.
- **Single snapshot**: compute the authorization fingerprint from one assembled
  evidence object; do not combine fresh CI with a stale reviewer comment.
- **Authorization invalidation**: compare exact PR, exact SHA, and exact
  fingerprint immediately before audit verification and merge.
- **Time-of-check/time-of-use**: after the pre-attempt audit and immediately
  before the command, live-read PR head/state again. Any change invalidates the
  authorization and returns to evidence collection.
- **Bounded action**: one authorization permits one named admin merge attempt.
  Retries after a failed command require the human to see the result and
  explicitly authorize another attempt.
- **Read-only gate**: the delegated gate remains incapable of reviewer runs,
  comments, labels, tracker updates, or merges; existing mutation-guard tests
  remain green.

---

## Testing Strategy

**Test types**: Shell unit/integration tests with mocked `gh` and fixture JSON;
documentation/mirror smoke; non-destructive live readback on a test PR when
available.

**Key scenarios to test**:

1. Green CI + zero blockers + non-green reviewer check + verified current
   denial reports access restriction separately (AC-1).
2. Failing/incomplete CI overrides denial evidence and never presents bypass
   (AC-2).
3. Blocking reviewer findings/unresolved threads override denial evidence
   (AC-3).
4. Missing, stale, contradictory, or unknown evidence fails closed (AC-4).
5. Verified restriction names App-access remediation as primary (AC-5).
6. Sole blocker presents exact evidence and the named admin command without
   executing it (AC-6).
7. No direct named authorization means no authorized outcome or admin command
   execution (AC-7).
8. Head or fingerprint change invalidates authorization (AC-8).
9. Stable audit exists before the attempt and is updated after rejection,
   success, or failure (AC-9).
10. `mayMerge`, delegated mode, epic policy, checkpoint satisfaction, or batch
    approval alone cannot authorize the bypass (AC-10).
11. Haystack guide includes org/repo App preflight and expected test-PR signal
    (AC-11).
12. Future implementation handoff retains the pending security checkpoint
    (AC-12).
13. Canonical protocol, gate output, agent/skill mirrors, integration guide,
    operator summary, and audit use the same matrix outcomes/actions (AC-13).

**Smoke test runbook**:
`docs/testing/workflow/1288-access-restricted-reviewer-checks.smoke-test.md`

**Regression suite**: The shell tests listed under **Files to Modify** are the
automated regression suite. Run focused tests first, then the repository's
workflow shell suite or equivalent CI entrypoint.

**Seed data**: Fixture JSON and mocked `gh` responses only; no database or
production pull request is required.

**Residual verification strategy**: This is pattern-completeness work across
mirrored merge surfaces. Before implementation readiness, rerun the
Verification Log searches and attach live output to the implementation PR.
Every remaining `merge_allowed`, direct `gh pr merge`, batch-merge routing, and
audit-trail surface must either implement/cross-reference the exceptional
branch or have a recorded out-of-scope rationale. Evidence source: live path
list plus the smoke matrix, not the frozen count in this plan.

---

## Seed Data

| Entity | Values / scenario | File |
| --- | --- | --- |
| Gate evidence fixture | Current PR/SHA, green CI, clean reviewer, forbidden reviewer check | `scripts/development-workflow/tests/test-run-epic-delegated-gate.sh` |
| Negative fixtures | CI failure, blocking findings, stale SHA, changed fingerprint, missing denial, multiple blockers | Same test file |
| CI check-rollup fixture | Default/custom reviewer name, status/conclusion, details URL, current timestamp | `scripts/development-workflow/tests/test-workflow-orchestration-product-repo-aware.sh` |
| Audit fixture | Authorization, evidence fingerprint, pre-attempt state, rejected/merged/failed results | `scripts/development-workflow/tests/test-run-epic-audit-trail.sh` |

No application seed data or production data is used.

---

## Documentation Updates

Performed during implementation, not on this Plan Ready branch:

- [ ] `docs/workflow/development-workflow/guardrails-enforcement.md` — canonical
      exceptional Gate 5 contract.
- [ ] `docs/workflow/development-workflow/protocols/90-batch-orchestrate-work-protocol.md`
      — batch supervision and per-PR authorization.
- [ ] `docs/workflow/development-workflow/protocols/91-orchestrate-work-protocol.md`
      — single-item merge path.
- [ ] `docs/workflow/development-workflow/protocols/94-batch-merge-protocol.md`
      — narrow batch route exception.
- [ ] `docs/workflow/development-workflow/protocols/95-run-epic-protocol.md` —
      epic child merge path.
- [ ] `docs/workflow/development-workflow/integrations/haystack-triage.md` —
      organization/repository access preflight and denial troubleshooting.
- [ ] `docs/workflow/development-workflow/integrations/haystack.md` — add one
      cross-reference to the canonical preflight; do not duplicate setup text.
- [ ] `docs/workflow/development-workflow/README.md` — add a concise linked
      summary of the remediation-first human-only exception.
- [ ] Agent/skill mirror files enumerated under **Files to Modify**.
- [ ] `CHANGELOG.md` — under `[Unreleased]` / `### Changed`, add:

      ```text
      - **Access-restricted reviewer merge gate** (#1288): distinguishes verified reviewer App-access restrictions from CI and review failures, prefers access remediation, and permits an audited protection bypass only after fresh named human authorization.
      ```

- [ ] `AGENTS.md` — no change expected; it links canonical workflow protocols
      and does not define the exceptional merge gate. Update only if live
      implementation search finds contradictory repository-wide guidance.

---

## Risks and Mitigations

| Risk | Likelihood | Impact | Mitigation |
| --- | --- | --- | --- |
| A 403-like string is mistaken for verified provider denial | Med | High | Require typed provider reason/source and current non-green configured check; negative lookalike tests |
| Authorization survives a pushed commit or changed gate evidence | Med | High | Exact SHA plus canonical material-evidence fingerprint and immediate pre-command readback |
| Existing delegated authority is misused as admin authorization | Med | High | Separate exceptional outcome, explicit non-substitution text/tests, and no helper executes `--admin` |
| Audit is written after rather than before the privileged action | Low | High | Gate requires verified pre-attempt marker before authorized outcome; protocol orders audit then command |
| Batch direct-merge exception expands beyond the named PR | Low | High | Per-PR fingerprint/authorization; unaffected PRs stay in Protocol 94; rediscover after the one action |
| Reviewer checks are accidentally reclassified as CI | Med | Med | Additive structured output; retain legacy CI counts and regression tests |
| Mirror surfaces drift | Med | Med | Full file enumeration, live residual search, consistency matrix, and smoke assertions |
| Audit comment leaks local paths or tokens | Low | High | Reuse redaction filter; add special-character and secret-like fixture tests |
| Implementation checkpoint is lost after plan merge | Low | High | Dedicated plan section, PR handoff note, and smoke assertion for future-stage pending state |

---

## Code Samples

Illustrative only; adapt field names to the existing helper conventions during
implementation.

### Exceptional gate result

```json
{
  "decision": "human_required",
  "mergePermitted": false,
  "reviewerAccess": {
    "classification": "authorization_required",
    "primaryAction": "restore repository or organization App access",
    "pullRequest": 42,
    "headSha": "abc123",
    "evidenceFingerprint": "sha256:...",
    "proposedAction": "gh pr merge 42 --admin"
  }
}
```

### Current named authorization

```json
{
  "pullRequest": 42,
  "headSha": "abc123",
  "evidenceFingerprint": "sha256:...",
  "authorizedBy": "named human",
  "authorizedAt": "ISO-8601 timestamp",
  "authorizationText": "Approve the admin merge for PR #42 at abc123"
}
```

These examples do not authorize any real action and must not be copied as
production evidence without a live human decision.

---

## Implementation Order

1. **Extend CI evidence output** — Update `pr-ci-loop.sh` and its product-aware
   test fixture to emit current structured reviewer-check evidence while
   preserving all legacy CI fields/results. Run the focused test and confirm a
   non-green configured reviewer check still yields green CI when real CI is
   green.
2. **Implement delegated-gate classification** — Extend
   `run-epic-delegated-gate.sh` with canonical evidence normalization,
   fingerprinting, precedence, freshness, authorization, and audit checks from
   AD-1 through AD-4. Add all parser-risk and matrix tests before changing
   workflow prose.
3. **Implement two-phase audit record** — Extend
   `run-epic-audit-trail.sh` and its tests with the stable access-bypass marker,
   required fields, redaction, pre-attempt verification fields, and final
   rejected/merged/failed updates.
4. **Update canonical guardrails and single/epic protocols** — Edit
   `guardrails-enforcement.md`, Protocol 91, and Protocol 95 so they use the
   exact helper outcomes and evidence field names implemented in Steps 2–3.
   Preserve the matrix precedence and the no-helper-admin rule.
5. **Update batch route** — Edit Protocols 90 and 94 with the narrow per-PR
   exception, fresh-base requirement, separate authorization, sequential
   rediscovery, and unchanged normal batch behavior.
6. **Update agent/skill mirrors** — Apply the non-substitution and exceptional
   routing rules to every file enumerated under **Agent and skill mirrors**.
   Preserve tool-specific frontmatter and keep detailed logic canonical in the
   protocols.
7. **Update Haystack setup guidance** — Add the organization/repository App
   access preflight, expected test-PR signal, local-auth distinction, 403
   troubleshooting, and remediation-first direction to `haystack-triage.md`;
   add the planned cross-references/summary in `haystack.md` and `README.md`
   without duplicating the matrix.
8. **Run residual consistency search** — Rerun the Verification Log path
   searches. Confirm each relevant surface implements/cross-references the
   matrix and that no prose says batch/delegated authority itself permits
   `--admin`. Attach the live path/disposition list to the implementation PR.
9. **Run validation** — Execute focused shell tests, ShellCheck for changed
   scripts, `python3 scripts/lint/workflow-shell-guard-lint.py --base-ref
   origin/develop`, Markdown lint/heuristic lint, and the smoke runbook. Confirm
   no test invokes a real mutating `gh` command.
10. **Apply implementation documentation** — Add the exact CHANGELOG literal
    from **Documentation Updates** and the planned README/Haystack
    cross-references.
11. **Preserve the security checkpoint** — In the implementation PR evidence,
    report issue #1288's implementation/security checkpoint as pending. Stop
    before delegated merge until a human reviews this security-sensitive
    implementation approach and the checkpoint lifecycle records the result.
12. **Open the implementation PR** — Use
    `feature/1288-access-restricted-reviewer-checks` targeting `develop`.
    Complete internal review, reviewer loop, CI, matrix evidence, checkpoint,
    and normal readiness gates. No plan-stage artifact alone counts as the
    implementation.

---

## Spec-to-Plan Coverage

| Spec objective / AC | Plan coverage |
| --- | --- |
| OBJ-1 / AC-1–AC-4: distinguish access, CI, review, insufficient evidence | AD-2–AD-4; delegated-gate matrix; parser tests; smoke Steps 1–4 |
| OBJ-2 / AC-5: remediation first | AD-4; matrix; canonical protocols; Haystack guide; smoke Step 5 |
| OBJ-3 / AC-6: evidence-based human-only option | AD-3–AD-7; output contract; smoke Step 6 |
| OBJ-4 / AC-7, AC-8, AC-10: named current authorization only | AD-3, AD-4, AD-6; exact SHA/fingerprint tests; smoke Steps 6–8 |
| OBJ-5 / AC-9: audit before action and final result | AD-5; audit helper/tests; smoke Step 8 |
| OBJ-6 / AC-11: organization-access preflight | Reviewer Integration Guidance; smoke Step 5 |
| AC-12: pending implementation security checkpoint | Dedicated checkpoint section; Implementation Order 11; smoke Step 10 |
| AC-13: matrix consistency across surfaces | Decision-Gate Consistency Matrix; full mirror enumeration; residual strategy; smoke Step 9 |

---

## Document Quality Gate

- Spec/brief coverage: Checked — every objective and AC maps to implementation
  steps and smoke assertions.
- Implementation-order consistency: Checked — helper names, evidence fields,
  audit ordering, protocol order, and file lists agree.
- Verification support: Checked — existing raw signals, gate surfaces, audit
  ownership, and batch-route claims cite live Verification Log queries/files.
- Behavioral guarantees: Checked — fail-closed behavior uses explicit
  precedence, exact SHA/fingerprint checks, pre-attempt audit presence, and a
  one-attempt authorization boundary.
- Complex workflow decision-gate matrix: Checked — matrix includes inputs,
  outcomes, next actions, mirror surfaces, and examples.
- Parser/API/snapshot checklist: Checked — concrete edge cases, test-file
  mappings, additive output compatibility, and single-snapshot rules are
  included.
- Concurrent-event checklist: Not applicable — no concurrent event sources or
  shared mutable asynchronous state.
- Cross-cutting checklist: Not applicable — this changes one specific merge
  gate rather than a generic quality/compliance checklist.
- CHANGELOG literal format: Checked — implementation literal uses the required
  bold-title and issue-number format.
- Design fidelity: Not applicable — no UI or design assets.
