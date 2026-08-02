# Agent Behavior No-Force-Push Guard - Implementation Plan

**Spec**: [Agent Behavior No-Force-Push Guard - Spec](1_1423-agent-behavior-no-force-push_specs.md)
**Smoke test runbook**: [No-force-push guard smoke test](../../../testing/workflow/1423-agent-behavior-no-force-push.smoke-test.md)

---

## Summary

**Approach**: Add a reusable workflow push guard that owns workflow PR branch
push execution after publication. The helper will block `--force` and
`--force-with-lease` unless a narrowly scoped, single-use authorization record
from a trusted human-controlled source matches the canonical repository, full
branch ref, destructive action, expected remote tip, authenticated operator, and
repository-scoped PR number; protocol and agent guidance will route spec, plan,
implementation, review-fix, and batch supervision flows through that guard.

**Estimated complexity**: M

**Rationale**: The behavior spans shell tooling, protocols, agent/skill
guidance, and tests. The core helper is small, but the risky part is making all
workflow branch-update surfaces consistently reference one guard without
creating a parallel policy model.

**Dependencies**: None. The approved spec for issue #1423 is merged into
`develop` and this plan can be implemented independently of #1424.

---

## Verification Log

| Check | Command / query | Result |
| --- | --- | --- |
| Repo revision | `git rev-parse --short HEAD` | `54f1e0e` |
| Template-fit check | Read `.ai-dev-workflow.yaml` and approved spec | `template.is_template: true`; spec changes generic workflow tooling, so it passes. |
| Current batch scope | Parent `/run-items` invocation | Frozen scope: `#1423,#1424`; relationship decision recorded as orthogonal. |
| Same-surface open PRs | `gh pr list --base develop --state open --json number,title,headRefName,files --jq '.[] | {number,title,headRefName,files:[.files[].path]}'` | No open PRs targeting `develop`; no same-surface operational conflict. |
| Published branch update policy | `rg -n "Published branch updates|force-push|force-with-lease" docs/best-practices/2-version-control.md AGENTS.md` | Policy already forbids published-history rewrites without explicit human approval. |
| Branch-update surface inventory | Python inventory over `scripts/development-workflow`, `docs/workflow/development-workflow/protocols`, `.agents/skills`, `.codex/skills`, `.claude/agents`, `.cursor/agents`, `.claude/commands`, and `.cursor/commands` matching `\bgit(?:\s+-C\s+\S+)?\s+push\b` and classifying force flags | 39 push lines in 22 files; 0 current force-push lines. Inventory includes raw `git push`, `git -C ... push`, protocol snippets, command docs, and test-only fixture pushes. Implementation must classify force behavior, remote, wrapper form, multiline form, and test scope before changing callers. |
| Agent and skill guidance surface search | `rg -l "commit and push|push|branch update|review-fix|BATCH_CONTEXT|workflow branch|implementation-plan|spec/" .claude/agents .cursor/agents .codex/skills .agents/skills \| wc -l` | 46 files mention branch, push, stage, or review-fix behavior; implementation must rerun this search and classify every hit as updated or out of scope. |
| Existing branch reuse guard | `sed -n '1,220p' scripts/development-workflow/validate-branch-reuse.sh` | Existing guard blocks unsafe branch reuse/rewrite recovery text but does not guard push execution. |
| Existing risk classifier blockers | `rg -n "force_push_required|destructive_action_required" scripts/development-workflow/tests/test-run-epic-risk-classifier.sh scripts/development-workflow/run-epic-risk-classifier.sh` | Existing risk classifier already emits hard blockers that must remain independent from any push exception. |

---

## Cross-Cutting Operational Assumption Check

### Applicable

| Assumption surface | Recorded value | Authoritative source | Verified at | Bounded cross-check scope | Result |
| --- | --- | --- | --- | --- | --- |
| Artifact owner and base branch for this template workflow item | `single_repo`, artifact base `develop` | `.ai-dev-workflow.yaml`, parent bounded prelude, `git rev-parse --short origin/develop` | `2026-08-01T18:57:58Z`, repo `54f1e0e` | Current invocation items `#1423,#1424`; no open PRs targeting `develop` at plan start | `Verified` |
| No-force-push policy source | Published PR branches must use follow-up commits unless exact human authorization exists | `docs/best-practices/2-version-control.md`, `AGENTS.md`, approved spec #1423 | `2026-08-01T18:57:58Z`, repo `54f1e0e` | Same current batch only; #1424 is orthogonal and covers mergeability rechecks, not branch-history rewrites | `Verified` |

---

## Complex Workflow Decision-Gate Matrix

| Gate input | Allowed outcome | Required next action | Mirror surfaces |
| --- | --- | --- | --- |
| Non-destructive branch update or first push of an unpublished branch | `push_allowed` | Execute through the guard and record safe update outcome | Protocol 03, Protocol 91, batch/review-fix guidance, Codex/Claude/Cursor implementer guidance |
| Destructive push requested with no matching authorization | `blocked_no_force_push_authorization` | Stop before push; name branch, action, missing evidence, and safe follow-up commit path | Shared helper output, Protocol 03, Protocol 90, Protocol 94, agent/skill files |
| Authorization matches canonical repository, full branch ref, action, expected remote tip, authenticated operator, repository-scoped PR number, trusted source, and unclaimed single-use token | `authorized_once` | Atomically claim the authorization, execute a server-side conditional ref update with the full expected tip, then consume the claim; roll back the claim if the conditional update fails without mutation | Shared helper, smoke runbook, unit tests |
| Authorization exists but scope, source trust, writer authority, token claim, or remote tip validation fails | `blocked_stale_or_mismatched_authorization` | Stop before mutation and request fresh exact authorization | Shared helper, unit tests, operational visibility docs |
| Risk classifier reports `force_push_required` or `destructive_action_required` | `risk_blocker_remains` | Keep the PR or batch blocked unless the normal delegated gate separately permits an unrelated action; do not treat push authorization as risk clearance | `run-epic-risk-classifier.sh`, delegated gate docs, Protocol 90 |

---

## Layer-by-Layer Changes

### Workflow Scripts

- [ ] Add `scripts/development-workflow/workflow-branch-push-guard.sh`.
  - Expose one non-bypassable interface for workflow branch updates:
    `workflow-branch-push-guard.sh --repo-root <path> --remote <name> --repo <owner/repo> --branch-ref refs/heads/<branch> --mode normal|force|force-with-lease --pr <number> [--expected-remote-tip <sha>] [--authorization-json <file>] -- <git-push-args>`.
    The helper executes the push itself after validation. Callers must not run a
    separate raw `git push` for a workflow PR branch update once this helper is
    available.
  - Validate required arguments before any GitHub or Git command: repository
    root, canonical repository, full branch ref, remote, push mode, PR number,
    expected remote tip for destructive updates, and optional authorization
    JSON.
  - Resolve and normalize the named remote URL before remote-tip lookup,
    authorization validation, or push execution. The normalized remote
    repository must match `--repo`; a fork, different owner/repo, malformed URL,
    or unresolvable remote is a helper failure and must not be treated as an
    unpublished branch or valid authorization target.
  - Classify push modes as `normal`, `force`, or `force-with-lease`.
  - Allow normal pushes and unpublished local-only amend follow-ups without
    authorization only when `git ls-remote --exit-code <remote> <full-ref>`
    returns Git's explicit no-match status for the full branch ref immediately
    before first publish. Local tracking metadata or absence of an upstream
    branch is not sufficient proof that a branch is unpublished. Authentication,
    transport, malformed-remote, server, and every other lookup error must exit
    as helper failure, not as `unpublished_ref_allowed`.
  - Block destructive updates unless a matching trusted authorization record is
    present. A PR-only match is never sufficient; the record must match the
    canonical repository and full branch ref, with PR number as an additional
    repository-scoped constraint.
  - Use one canonical JSON authorization schema. Required fields:
    `schema_version`, `authorization_id`, `canonical_repo`, `pr_number`,
    `branch_ref`, `action`, `expected_remote_tip`, `operator_login`,
    `authorized_by`, `source_kind`, `source_id`, `source_url`,
    `source_fingerprint_sha256`, `issued_at`, `expires_at`, and
    `single_use: true`.
  - Treat a local JSON file as a cache, not proof. The helper must verify the
    authorization against a trusted, non-agent-controlled source such as a
    GitHub issue or PR comment authored by the authenticated human operator, or
    an equivalent parent-run approval source whose writer identity and source
    fingerprint are recorded in the run summary. Agent-authored or tampered
    records must block.
  - For authorized destructive updates, claim the single-use authorization
    before attempting the update through a shared authoritative claim service.
    The MVP claim service is a GitHub issue or PR comment marker containing
    `authorization_id`, `canonical_repo`, `branch_ref`, expected tip, run id,
    and claim state. After creating the marker, the helper must re-query all
    claim markers for that authorization and proceed only if its server-created
    marker is the earliest non-rolled-back claim for the same authorization.
    This coordinates separate processes and workspaces; local lock files alone
    are insufficient. If the conditional ref update fails without mutation, post
    a rollback marker for that claim so a later run can request fresh
    authorization rather than treating the failed claim as a successful use.
  - Execute destructive updates as a server-side conditional ref update using
    the full expected tip, such as `git push --force-with-lease=<full-ref>:<expected-tip>`
    for the matching full ref. Do not perform a separate tip read followed by an
    unqualified force push. If the conditional update fails because the remote
    tip changed, roll back the local claim, leave the authorization unconsumed
    as a successful use, and require fresh authorization for retry.
  - Emit stable key/value output such as `PUSH_GUARD_RESULT=allowed|blocked`,
    `PUSH_GUARD_REASON=...`, `BRANCH_REF=...`, `EXPECTED_REMOTE_TIP=...`, and
    `AUTHORIZATION_CONSUMED=true|false`.
  - Exit `0` when the guarded push succeeds, `1` when policy blocks the push
    without remote mutation, and `2` for helper, input, authentication, or
    trusted-source verification failures.
  - Use these complete reason values: `normal_push_allowed`,
    `unpublished_ref_allowed`, `missing_authorization`,
    `untrusted_authorization_source`, `authorization_scope_mismatch`,
    `authorization_expired`, `authorization_already_claimed`,
    `remote_tip_mismatch`, `conditional_update_failed`, and `push_failed`.
- [ ] Add a small wrapper function in `scripts/development-workflow/workflow-lib.sh`
  only if it reduces duplication for existing scripts; otherwise keep the guard
  as a standalone script to avoid broad library coupling.
- [ ] Update `scripts/development-workflow/batch-merge.sh` only where it pushes a
  target base or amends a local merge commit, documenting that local merge-commit
  amendment before publication is not a PR-branch force push.
- [ ] Ensure any branch update path that needs a pushed PR branch points callers
  to the guard rather than raw `git push --force*`.

### Protocols and Workflow Documentation

- [ ] Update `docs/workflow/development-workflow/protocols/03-implement-development-protocol.md`
  so implementation and review-fix branch updates must use follow-up commits on
  published branches and must run the guard before any destructive branch update.
- [ ] Update `docs/workflow/development-workflow/protocols/90-batch-orchestrate-work-protocol.md`
  so batch supervision preserves the no-force-push stop condition and treats
  exact force-push authorization as separate from delegated merge authority.
- [ ] Update `docs/workflow/development-workflow/protocols/91-orchestrate-work-protocol.md`
  so single-item runs apply the guard before branch rewrites in spec, plan, or
  implementation readiness loops.
- [ ] Update `docs/workflow/development-workflow/protocols/94-batch-merge-protocol.md`
  to state that conflict recovery and remaining-PR updates must not force-push
  without the guard and exact authorization.
- [ ] Update `docs/best-practices/2-version-control.md` only if needed to point
  from the existing policy to the executable guard.
- [ ] Update `scripts/development-workflow/README.md` with the new helper's
  purpose, inputs, outputs, and authorized exception contract.

### Agent and Skill Guidance

- [ ] Update stage agents that can create, update, or fix workflow PR branches:
  `.claude/agents/product-manager.md`, `.cursor/agents/product-manager.md`,
  `.claude/agents/tech-lead.md`, `.cursor/agents/tech-lead.md`,
  `.claude/agents/developer.md`, `.cursor/agents/developer.md`,
  `.claude/agents/code-reviewer.md`, `.cursor/agents/code-reviewer.md`,
  `.claude/agents/spec-reviewer.md`, `.cursor/agents/spec-reviewer.md`,
  `.claude/agents/implementation-plan-reviewer.md`, and
  `.cursor/agents/implementation-plan-reviewer.md`.
- [ ] Update orchestration and review-loop agents that supervise pushed PR
  branches: `.claude/agents/item-orchestrator.md`,
  `.cursor/agents/item-orchestrator.md`, `.claude/agents/orchestrator.md`,
  `.cursor/agents/orchestrator.md`,
  `.claude/agents/automated-reviewer-loop.md`, and
  `.cursor/agents/automated-reviewer-loop.md`.
- [ ] Update Codex skills for stage execution and review-fix loops:
  `.codex/skills/workflow-spec-writer/SKILL.md`,
  `.codex/skills/workflow-plan-writer/SKILL.md`,
  `.codex/skills/workflow-implementer/SKILL.md`,
  `.codex/skills/workflow-spec-reviewer/SKILL.md`,
  `.codex/skills/workflow-plan-reviewer/SKILL.md`,
  `.codex/skills/workflow-code-reviewer/SKILL.md`,
  `.agents/skills/workflow-spec-writer/SKILL.md`,
  `.agents/skills/workflow-plan-writer/SKILL.md`,
  `.agents/skills/workflow-implementer/SKILL.md`,
  `.agents/skills/workflow-spec-reviewer/SKILL.md`,
  `.agents/skills/workflow-plan-reviewer/SKILL.md`, and
  `.agents/skills/workflow-code-reviewer/SKILL.md`.
- [ ] Update Codex orchestration and batch skills:
  `.codex/skills/workflow-item-orchestrator/SKILL.md`,
  `.codex/skills/workflow-orchestrator/SKILL.md`,
  `.agents/skills/run-item/SKILL.md`, `.agents/skills/run-items/SKILL.md`,
  `.codex/skills/batch-merge/SKILL.md`, and any matching
  `agents/openai.yaml` prompt files whose branch-update wording would otherwise
  contradict the guard.
- [ ] Rerun the guidance surface search from the Verification Log before
  submitting; every hit must be updated or explicitly documented as out of
  scope in the implementation PR's self-review log.

### Tests and Validation

- [ ] Add `scripts/development-workflow/tests/test-workflow-branch-push-guard.sh`
  with fake Git remotes and a mocked authorization source.
- [ ] Extend `scripts/development-workflow/tests/test-run-epic-risk-classifier.sh`
  or add a focused test to confirm `force_push_required` and
  `destructive_action_required` remain hard blockers even when an exact branch
  update authorization exists.
- [ ] Extend `scripts/development-workflow/tests/test-workflow-hub-docs.sh` only
  if its current no-force-push expectations need updated allowed examples.
- [ ] Add or update a smoke runbook at
  `docs/testing/workflow/1423-agent-behavior-no-force-push.smoke-test.md`.

---

## Testing Strategy

**Test types**: Unit / Integration-style shell tests / Smoke

**Key scenarios to test**:

1. Unauthorized `--force` or `--force-with-lease` on a published PR branch
   returns blocked output before mutation and names that general workflow
   confirmation is insufficient. Maps to AC1 and AC2.
2. A safe follow-up commit push on an existing PR branch proceeds through the
   non-destructive path. Maps to AC3.
3. A local amend before first publication remains allowed. Maps to AC4.
   First-publication detection must be based on a fresh remote-ref existence
   check, not local tracking state.
4. A single-use authorization matching authenticated operator, trusted source,
   canonical repository, repository-scoped PR number, full ref, action, and
   expected remote tip permits exactly one conditional destructive update. Maps
   to AC5.
5. Wrong repository, same-named branch in another repository, PR-only
   authorization, wrong action, stale remote tip, later push, expired
   authorization, tampered source fingerprint, unauthorized writer, concurrent
   same-record attempt, or replay after use blocks. Maps to AC6 and AC7.
6. Risk classifier hard blockers remain independent from the push guard. Maps
   to AC8.
7. Spec, plan, implementation, review-fix, and batch-supervision guidance all
   point to the same guard. Maps to AC9 and AC10.

**Smoke test runbook**: `docs/testing/workflow/1423-agent-behavior-no-force-push.smoke-test.md`

**Regression suite**: Add a committed shell test under
`scripts/development-workflow/tests/` and wire it into the existing workflow
test command pattern used by nearby tests.

### Parser-Risk Addendum

This plan is not parser-risk. It adds shell validation around Git branch update
operations and one canonical JSON authorization input, but it does not introduce
a regex-heavy scanner, structured-text parser, lint rule, or tokenizer. The
implementation must still validate JSON with `jq -e` and explicit empty-output
guards per the shell quality checklist.

---

## Seed Data

| Entity | Values / Scenario | File |
| --- | --- | --- |
| Temporary Git repository | Local branch, remote branch, matching and stale remote tips | Created inside the shell test temp directory |
| Authorization fixture | Matching, wrong-repo, PR-only, wrong-ref, wrong-action, stale-tip, expired, tampered, unauthorized-writer, concurrent, and replayed records | Created inside `test-workflow-branch-push-guard.sh` temp files with live trusted-source verification mocked |

---

## Documentation Updates

The authoritative documentation and guidance inventory is in
**Layer-by-Layer Changes** above. The implementation PR must update those files
or record each matched file as out of scope in its self-review log. `REVIEW.md`
is updated only if the implementation introduces reviewer-visible checklist
behavior beyond the existing guardrails section.

---

## Risks & Mitigations

| Risk | Likelihood | Impact | Mitigation |
| --- | --- | --- | --- |
| A workflow path still uses raw destructive push guidance | Med | High | Implementation must rerun the branch-update surface search and document each remaining hit as updated or out of scope. |
| Authorization format becomes a broad bypass | Low | High | Bind authorization to canonical repo, repository-scoped PR number, full branch ref, exact action, expected remote tip, authenticated operator, trusted source, and single-use claim. |
| Remote tip changes after validation | Med | High | Use a server-side conditional ref update with the full expected tip and fail closed when the remote differs. |
| Guard conflicts with legitimate local amend before first push | Low | Med | Explicitly distinguish unpublished local history from published remote branch rewrites by checking fresh remote-ref existence in tests. |
| Risk classifier semantics are weakened accidentally | Low | High | Keep risk classifier blockers separate and add regression coverage for unchanged blocker behavior. |

---

## Code Samples

No production-ready code samples are included. The implementation PR should add
the shell helper and tests directly.

---

## Implementation Order

1. Create `scripts/development-workflow/workflow-branch-push-guard.sh` with Bash
   3.2-compatible argument parsing, ref validation, remote-tip lookup, safe
   update classification, canonical JSON authorization validation,
   trusted-source verification, atomic single-use claiming, server-side
   conditional update execution, and stable key/value output.
   The helper must bind the named remote URL to `--repo` before authorization
   processing and must fail closed on remote lookup errors.
   The unpublished-branch allowance must use a fresh remote-ref existence check
   such as `git ls-remote --exit-code <remote> <full-ref>`, accepting only the
   explicit no-match status as unpublished proof, and must not trust stale local
   upstream metadata.
2. Add `scripts/development-workflow/tests/test-workflow-branch-push-guard.sh`
   covering unauthorized destructive pushes, safe follow-up pushes, local-only
   amend allowance, authorized single-use destructive update, stale-tip failure,
   scope mismatches, PR-only authorization, tampered records, unauthorized
   writers, cross-workspace atomic concurrent claims, remote URL mismatch,
   remote lookup failure, conditional-update rollback, expiry, and replay.
3. Update implementation, orchestration, and batch protocols to require the
   helper before destructive PR branch updates and to keep general workflow
   approval/delegated merge authority separate from force-push authorization.
4. Update Claude, Cursor, Codex, and command skill guidance that can perform or
   supervise workflow branch updates.
5. Update `scripts/development-workflow/README.md` and, if needed,
   `docs/best-practices/2-version-control.md` to document the helper contract.
6. Add the smoke runbook and ensure it maps each acceptance criterion to an
   executable validation step.
7. Update `CHANGELOG.md` under `[Unreleased]` in the implementation PR using:
   `- **Guard workflow branch pushes** (#1423): Add an execution-time no-force-push guard for workflow PR branch updates and exact human-authorized exceptions.`
8. Run verification:
   - `bash scripts/development-workflow/tests/test-workflow-branch-push-guard.sh`
   - `bash scripts/development-workflow/tests/test-run-epic-risk-classifier.sh`
   - `bash scripts/development-workflow/tests/test-workflow-hub-docs.sh`
   - `shellcheck --severity=warning scripts/development-workflow/workflow-branch-push-guard.sh scripts/development-workflow/tests/test-workflow-branch-push-guard.sh`
   - `python3 scripts/lint/workflow-shell-guard-lint.py --base-ref origin/develop`
   - `npx markdownlint-cli2 "docs/specs/developments/**/*.md" "docs/testing/workflow/**/*.md" "CHANGELOG.md"`
   - `find docs/specs/developments docs/testing/workflow -name "*.md" -print0 | xargs -0 python3 scripts/lint/markdown-heuristic-lint.py CHANGELOG.md`
9. Complete the Protocol 03 Pre-Submission Self-Review Pass, including the
   complex decision-gate matrix above, before opening the implementation PR.
   The self-review log must include the complete push-inventory classification
   by force behavior, remote, wrapper, multiline form, and test scope.
