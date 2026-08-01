# Agent Behavior No-Force-Push Guard - Implementation Plan

**Spec**: [Agent Behavior No-Force-Push Guard - Spec](1_1423-agent-behavior-no-force-push_specs.md)
**Smoke test runbook**: [No-force-push guard smoke test](../../../testing/workflow/1423-agent-behavior-no-force-push.smoke-test.md)

---

## Summary

**Approach**: Add a reusable workflow push guard that is the only approved path
for workflow PR branch pushes after publication. The helper will block
`--force` and `--force-with-lease` unless a narrowly scoped, single-use
authorization record matches the repository, PR or branch, full ref, destructive
action, expected remote tip, and authenticated operator; protocol and agent
guidance will route spec, plan, implementation, review-fix, and batch
supervision flows through that guard.

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
| Branch-update surface search | `rg --pcre2 -n "git push( --set-upstream|-u)? origin(?! --delete)|git push .*--force|force-with-lease|commit --amend|git commit --amend" scripts/development-workflow docs/workflow/development-workflow/protocols .agents/skills .codex/skills .claude/agents .cursor/agents .claude/commands .cursor/commands` | 10 matches across `batch-merge.sh`, Protocols 05/05b/06/90/94, `.codex/skills/batch-merge/SKILL.md`, and `test-workflow-hub-docs.sh`. |
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
| Non-destructive branch update or first push of an unpublished branch | `push_allowed` | Push normally and record safe update outcome | Protocol 03, Protocol 91, batch/review-fix guidance, Codex/Claude/Cursor implementer guidance |
| Destructive push requested with no matching authorization | `blocked_no_force_push_authorization` | Stop before push; name branch, action, missing evidence, and safe follow-up commit path | Shared helper output, Protocol 03, Protocol 90, Protocol 94, agent/skill files |
| Authorization matches repository or PR, full branch ref, action, expected remote tip, authenticated operator, and one execution or unexpired TTL | `authorized_once` | Perform one conditional update only if the remote tip still matches; record consumption | Shared helper, smoke runbook, unit tests |
| Authorization exists but scope differs or the remote tip changed | `blocked_stale_or_mismatched_authorization` | Stop before mutation and request fresh exact authorization | Shared helper, unit tests, operational visibility docs |
| Risk classifier reports `force_push_required` or `destructive_action_required` | `risk_blocker_remains` | Keep the PR or batch blocked unless the normal delegated gate separately permits an unrelated action; do not treat push authorization as risk clearance | `run-epic-risk-classifier.sh`, delegated gate docs, Protocol 90 |

---

## Layer-by-Layer Changes

### Workflow Scripts

- [ ] Add `scripts/development-workflow/workflow-branch-push-guard.sh`.
  - Validate required arguments before any GitHub or Git command: repository
    root, branch ref, remote, push mode, PR number when available, expected
    remote tip for destructive updates, and optional authorization file.
  - Classify push modes as `normal`, `force`, or `force-with-lease`.
  - Allow normal pushes and unpublished local-only amend follow-ups without
    authorization.
  - Block destructive updates unless a matching authorization record is present.
  - For authorized destructive updates, verify the current remote tip still
    equals the authorized expected tip immediately before the update and fail
    closed when it does not.
  - Emit stable key/value output such as `PUSH_GUARD_RESULT=allowed|blocked`,
    `PUSH_GUARD_REASON=...`, `BRANCH_REF=...`, `EXPECTED_REMOTE_TIP=...`, and
    `AUTHORIZATION_CONSUMED=true|false`.
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

- [ ] Update `.claude/agents/developer.md` and `.cursor/agents/developer.md` to
  require the guard before destructive branch updates and to prefer follow-up
  commits on published PR branches.
- [ ] Update `.codex/skills/workflow-implementer/SKILL.md` and
  `.agents/skills/workflow-implementer/SKILL.md` with the same rule for Codex
  runs.
- [ ] Update `.codex/skills/batch-merge/SKILL.md` and
  `.agents/skills/run-items/SKILL.md` where batch conflict recovery or delegated
  merge supervision could otherwise imply destructive branch-history recovery.
- [ ] Check `.claude/commands/`, `.cursor/commands/`, `.codex/skills/`, and
  `.agents/skills/` for other direct force-push guidance before submitting; the
  implementation PR must either update each hit or record why it is out of
  scope.

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
4. A single-use authorization matching operator, repo or PR, full ref, action,
   and expected remote tip permits exactly one conditional destructive update.
   Maps to AC5.
5. Wrong repository, same-named branch in another repository, wrong action,
   stale remote tip, later push, expired authorization, or replay after use
   blocks. Maps to AC6 and AC7.
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
operations and JSON/key-value authorization input, but it does not introduce a
regex-heavy scanner, structured-text parser, lint rule, or tokenizer. The
implementation must still validate JSON with `jq -e` and explicit empty-output
guards per the shell quality checklist.

---

## Seed Data

| Entity | Values / Scenario | File |
| --- | --- | --- |
| Temporary Git repository | Local branch, remote branch, matching and stale remote tips | Created inside the shell test temp directory |
| Authorization fixture | Matching, wrong-repo, wrong-ref, wrong-action, stale-tip, expired, and replayed records | Created inside `test-workflow-branch-push-guard.sh` temp files |

---

## Documentation Updates

- [ ] `docs/workflow/development-workflow/protocols/03-implement-development-protocol.md` - require guarded branch updates and exact force-push authorization.
- [ ] `docs/workflow/development-workflow/protocols/90-batch-orchestrate-work-protocol.md` - preserve no-force-push policy during batch supervision and recovery.
- [ ] `docs/workflow/development-workflow/protocols/91-orchestrate-work-protocol.md` - apply the guard across spec, plan, and implementation item runs.
- [ ] `docs/workflow/development-workflow/protocols/94-batch-merge-protocol.md` - document guarded recovery after batch conflicts.
- [ ] `docs/best-practices/2-version-control.md` - link the published-branch rule to the executable guard if the implementation adds one.
- [ ] `scripts/development-workflow/README.md` - document the helper interface and output contract.
- [ ] `.claude/agents/developer.md` and `.cursor/agents/developer.md` - mirror implementer guidance.
- [ ] `.codex/skills/workflow-implementer/SKILL.md`, `.agents/skills/workflow-implementer/SKILL.md`, `.codex/skills/batch-merge/SKILL.md`, and `.agents/skills/run-items/SKILL.md` - mirror Codex and command-skill guidance.
- [ ] `REVIEW.md` - add review expectations only if the implementation introduces reviewer-visible checklist behavior beyond the existing guardrails section.

---

## Risks & Mitigations

| Risk | Likelihood | Impact | Mitigation |
| --- | --- | --- | --- |
| A workflow path still uses raw destructive push guidance | Med | High | Implementation must rerun the branch-update surface search and document each remaining hit as updated or out of scope. |
| Authorization format becomes a broad bypass | Low | High | Bind authorization to repo/PR, full branch ref, exact action, expected remote tip, operator, and single-use/expiry. |
| Remote tip changes after validation | Med | High | Re-read the remote tip immediately before the update and fail closed when it differs. |
| Guard conflicts with legitimate local amend before first push | Low | Med | Explicitly distinguish unpublished local history from published remote branch rewrites in tests. |
| Risk classifier semantics are weakened accidentally | Low | High | Keep risk classifier blockers separate and add regression coverage for unchanged blocker behavior. |

---

## Code Samples

No production-ready code samples are included. The implementation PR should add
the shell helper and tests directly.

---

## Implementation Order

1. Create `scripts/development-workflow/workflow-branch-push-guard.sh` with Bash
   3.2-compatible argument parsing, ref validation, remote-tip lookup, safe
   update classification, authorization matching, and stable key/value output.
2. Add `scripts/development-workflow/tests/test-workflow-branch-push-guard.sh`
   covering unauthorized destructive pushes, safe follow-up pushes, local-only
   amend allowance, authorized single-use destructive update, stale-tip failure,
   scope mismatches, expiry, and replay.
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
