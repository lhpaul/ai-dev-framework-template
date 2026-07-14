# Prevent Unsanctioned Nested Agent PRs - Implementation Plan

**Spec**: [1_1200-prevent-unsanctioned-nested-agent-prs_specs.md](1_1200-prevent-unsanctioned-nested-agent-prs_specs.md)
**Smoke test runbook**: [1200-prevent-unsanctioned-nested-agent-prs.smoke-test.md](../../../testing/workflow/1200-prevent-unsanctioned-nested-agent-prs.smoke-test.md)

---

## Summary

**Approach**: Add one reusable workflow guard script that inspects issue-scoped
worktrees, branches, open PRs, and explicit base-branch context before a nested
or spawned agent creates workflow artifacts. Wire that guard into the parent
orchestration checkpoints and stage handoff requirements so Protocols 90, 91,
and 95 keep parent-visible authority over any duplicate path or PR base.

**Estimated complexity**: M

**Rationale**: The behavior is conceptually narrow, but it crosses shared
workflow protocols, mirrored agent guidance, command-style skills, shell helper
tests, and PR creation paths. The main risk is incomplete propagation across
runner surfaces rather than algorithmic complexity.

**Dependencies**: The approved spec for issue #1200 is present on `origin/develop`.
No external service dependency beyond the existing `git` and `gh` workflow tooling.

---

## Verification Log

| Check | Command / query | Result |
| --- | --- | --- |
| Repo revision | `git rev-parse --short HEAD` | `d26edf4` |
| Template-fit check | Read `.ai-dev-workflow.yaml` and spec overview | `template.is_template: true`; spec improves generic workflow tooling and does not reference a downstream framework |
| Cross-cutting target search | `grep -rl "02-generate-implementation-plan-protocol\|03-implement-development-protocol" .claude/agents/ .cursor/agents/ .codex/skills/ \| sort` | 6 required plan/implementation guidance files: `.claude/agents/developer.md`, `.claude/agents/tech-lead.md`, `.codex/skills/workflow-implementer/SKILL.md`, `.codex/skills/workflow-plan-writer/SKILL.md`, `.cursor/agents/developer.md`, `.cursor/agents/tech-lead.md` |
| Workflow surface search | `rg -l "BATCH_CONTEXT|worktree path|worktree-path|base branch|base-branch|gh pr create|pr create|stage-agent handoff|Work Item Runner|Portfolio Orchestrator|item-orchestrator|run-items|run-item|run-epic" docs/workflow/development-workflow/protocols .claude/agents .cursor/agents .codex/skills .agents/skills scripts/development-workflow REVIEW.md \| sort` | 62 candidate workflow files; plan lists the required subset below and leaves unrelated reviewer, release, and cleanup surfaces unchanged |
| Current issue-scoped artifacts | `git worktree list --porcelain \| awk '/^worktree / {wt=$2} /^branch / {branch=$2; sub("^refs/heads/", "", branch); print wt "\t" branch}' \| grep '1200\|prevent-unsanctioned' || true` | One expected plan worktree: `.codex-worktrees/1200-prevent-unsanctioned-nested-agent-prs` on `implementation-plan/1200-prevent-unsanctioned-nested-agent-prs` |
| Current open PR collision check | `gh pr list --state open --search "1200 prevent-unsanctioned" --json number,headRefName,baseRefName,title --jq '.[] \| [.number,.headRefName,.baseRefName,.title] \| @tsv'` | No existing open PR for issue #1200 before this plan PR |

---

## Architecture Decisions

1. **Centralize detection in a shell helper**: implement
   `scripts/development-workflow/run-nested-artifact-guard.sh` instead of
   copying ad hoc `git worktree`, branch, and PR checks into each protocol. The
   helper is the enforcement mechanism for duplicate-artifact and base-context
   guarantees.
2. **Use explicit modes instead of implicit fallback**: the helper supports
   separate checks for `pre-create`, `pre-pr`, and `audit` so protocols can call
   the same tool with stage-appropriate stop behavior.
3. **Treat repository default branch as invalid fallback**: branch and PR
   creation require an approved base from parent context, direct operator input,
   or stage rules. A missing base is a stop, not a fallback to GitHub defaults.
4. **Keep parent summaries authoritative**: nested-agent stops and audit
   warnings must be re-emitted in the parent run summary. Private subagent output
   is not sufficient visibility.

---

## Files to Modify

### New or changed scripts

- [ ] `scripts/development-workflow/run-nested-artifact-guard.sh` - new helper
      that validates issue scope, expected branch, worktree path, approved base
      branch, local branches, remote branches, and open PRs.
- [ ] `scripts/development-workflow/open-product-pr.sh` - reject empty,
      unresolved, or conflicting base branch values before `gh pr create`.
- [ ] `scripts/development-workflow/tests/test-run-nested-artifact-guard.sh` -
      unit coverage for duplicate-artifact detection, missing-base refusal,
      wrong-base refusal, and parent-visible audit output.
- [ ] `scripts/development-workflow/README.md` - document the new helper's
      purpose, modes, and expected callers.

### Protocol documentation

- [ ] `docs/workflow/development-workflow/protocols/01-generate-spec-protocol.md`
      - require explicit base context before spec branch or PR creation.
- [ ] `docs/workflow/development-workflow/protocols/02-generate-implementation-plan-protocol.md`
      - require explicit artifact base context before plan branch or PR creation.
- [ ] `docs/workflow/development-workflow/protocols/03-implement-development-protocol.md`
      - require the duplicate/base guard before implementation-stage branch,
      commit, push, or PR creation.
- [ ] `docs/workflow/development-workflow/protocols/90-batch-orchestrate-work-protocol.md`
      - add parent audit checkpoints for explicit-list batches and require
      handoffs to pass approved item scope, branch, worktree path, and base.
- [ ] `docs/workflow/development-workflow/protocols/91-orchestrate-work-protocol.md`
      - add the single-item guard calls before stage handoff, push, PR creation,
      reviewer-loop entry, readiness update, and final summary.
- [ ] `docs/workflow/development-workflow/protocols/95-run-epic-protocol.md`
      - apply the same guard to epic-scoped delegated dispatch and summaries.

### Agent guidance

- [ ] `.claude/agents/orchestrator.md` - include the parent audit and handoff
      requirements for batch dispatch.
- [ ] `.cursor/agents/orchestrator.md` - mirror the batch dispatch requirements.
- [ ] `.claude/agents/item-orchestrator.md` - require guard calls and summary
      reporting for item-scoped runs.
- [ ] `.cursor/agents/item-orchestrator.md` - mirror item-scoped guard behavior.
- [ ] `.claude/agents/product-manager.md` - require explicit base context before
      spec branch or PR creation.
- [ ] `.cursor/agents/product-manager.md` - mirror spec-stage base-context rules.
- [ ] `.claude/agents/tech-lead.md` - require explicit artifact base context
      before plan branch or PR creation.
- [ ] `.cursor/agents/tech-lead.md` - mirror plan-stage base-context rules.
- [ ] `.claude/agents/developer.md` - require duplicate/base guard verification
      before implementation branch, push, and PR creation.
- [ ] `.cursor/agents/developer.md` - mirror implementation-stage guard rules.

### Codex and command-style skills

- [ ] `.codex/skills/workflow-orchestrator/SKILL.md` - pass approved scope,
      branch, worktree path, and base branch in item handoffs.
- [ ] `.codex/skills/workflow-item-orchestrator/SKILL.md` - run and report the
      guard during item execution.
- [ ] `.codex/skills/workflow-spec-writer/SKILL.md` - require explicit base
      context before spec PR creation.
- [ ] `.codex/skills/workflow-plan-writer/SKILL.md` - require explicit artifact
      base context before plan PR creation.
- [ ] `.codex/skills/workflow-implementer/SKILL.md` - require guard verification
      before implementation branch, push, and PR creation.
- [ ] `.agents/skills/run-work/SKILL.md` - ensure read-only routing remains
      non-mutating and handoffs include approved base context.
- [ ] `.agents/skills/run-items/SKILL.md` - require guard-aware explicit-list
      dispatch and parent-visible unexpected-fork summaries.
- [ ] `.agents/skills/run-item/SKILL.md` - require the item guard for standalone
      bounded item runs.
- [ ] `.agents/skills/run-item-work/SKILL.md` - mirror the deprecated alias.
- [ ] `.agents/skills/run-epic/SKILL.md` - require the guard for epic-scoped
      delegated dispatch.

### Review contract

- [ ] `REVIEW.md` - add review checks for duplicate-artifact guard coverage,
      explicit base-branch enforcement, and parent-visible fork warnings.

---

## Layer-by-Layer Changes

### Workflow Scripts

- [ ] Add `run-nested-artifact-guard.sh` with bash 3.2-compatible option parsing.
- [ ] Validate required inputs at startup: issue number, mode, expected head
      branch, approved base branch when branch or PR creation is possible, and
      expected worktree path when operating in `BATCH_CONTEXT=true`.
- [ ] Inspect issue-scoped local worktrees, local branches, remote branches, and
      open PRs. Use anchored issue/branch patterns so issue `1200` does not
      match unrelated issue numbers.
- [ ] Emit structured lines for protocol consumers, including `RESULT=clean`,
      `RESULT=blocked_duplicate`, `RESULT=missing_base`,
      `RESULT=wrong_base`, and `RESULT=unexpected_fork`.
- [ ] Include artifact fields in blocked or warning output: issue, expected
      branch, expected worktree, discovered worktree or branch, PR number, PR
      base, approved base, and required next action.
- [ ] Update `open-product-pr.sh` so the script refuses to run if `BASE_BRANCH`
      is empty or does not match an optional approved base passed by the caller.

### Orchestration Protocols

- [ ] Protocol 90 calls the helper during explicit-list pre-flight and after
      Work Item Runner return before readiness supervision. It reports any
      unexpected forks under the explicit item list summary.
- [ ] Protocol 91 calls the helper before creating a worktree, before dispatching
      a stage agent, before opening or converting a PR, and before final summary.
- [ ] Protocol 95 calls the helper before epic delegated dispatch and includes
      unexpected forks in the epic ledger or run summary.
- [ ] Protocols 01, 02, and 03 require stage agents to reject branch or PR
      creation when approved base context is missing, ambiguous, or conflicting.
- [ ] Every protocol caller cites the helper's structured `RESULT=` values and
      says whether each result blocks, warns, or allows continuation.

### Agent and Skill Guidance

- [ ] Update Claude, Cursor, Codex, and command-style skill surfaces listed in
      **Files to Modify** so every runner receives the same guard contract.
- [ ] Preserve existing worktree discipline text and add the duplicate/base
      guard as an additional pre-mutation check.
- [ ] Require every nested or spawned handoff that can mutate artifacts to carry
      issue number, expected branch, worktree path when isolated, approved base
      branch, and parent approval for any deliberate split path.

### Review Contract

- [ ] Add review checks to flag missing guard calls when PRs modify
      orchestration, stage-agent handoffs, branch creation, or PR creation.
- [ ] Add review checks for base-branch fallback language so documentation or
      code cannot rely on the GitHub default branch for workflow PRs.

### Database / Data Layer

- [ ] None. This workflow feature does not introduce persistent application data.

### Frontend / UI

- [ ] None. This repository change is workflow tooling and documentation only.

### Infrastructure / Configuration

- [ ] None. No CI, environment variable, secret, or deployment configuration
      changes are required.

---

## Parser-Risk Addendum

This plan is parser-risk because it introduces a workflow shell helper that
parses structured `git worktree`, `git branch`, `git ls-remote`, and `gh pr`
output and because protocol snippets will consume its structured result values.

### Edge-Case Enumeration

1. **Boundary issue numbers**: issue `1200` must match `feature/1200-slug`,
   `feature/ENG-1200-slug`, and `implementation-plan/1200-slug`, but must not
   match `feature/12000-slug`, `feature/31200-slug`, or `feature/foo-1200`.
2. **Branch-prefix lookalikes**: `fix/1200-slug` must not be confused with
   `hotfix/1200-slug`; branch prefix matching must be anchored.
3. **Existing canonical artifact**: the expected branch or worktree for the
   current item is allowed and reported as canonical, not a duplicate.
4. **Duplicate local worktree**: a second worktree for the same issue but a
   different branch or path blocks `pre-create` and reports the discovered path.
5. **Remote branch without local worktree**: an issue-scoped remote branch blocks
   new branch creation when it is not the expected branch.
6. **Open PR wrong base**: an issue-scoped PR whose base is `main` while the
   approved base is `develop` blocks `pre-pr`.
7. **Missing base**: branch or PR creation with an empty approved base returns
   `RESULT=missing_base`.
8. **Deliberate split path**: duplicate artifacts are allowed only when explicit
   parent or human split approval and explicit base branch are both present.
9. **Multiple artifacts in one scan**: output includes every discovered
   unexpected artifact, not only the first match.
10. **Empty command output**: empty worktree, branch, remote, or PR result sets
    produce `RESULT=clean` rather than parser failure.
11. **CLI/API failure**: failed `git` or `gh` calls return a non-clean result
    with a required action instead of silently proceeding.

### Unit Test Mapping

Add tests in `scripts/development-workflow/tests/test-run-nested-artifact-guard.sh`.

| Edge case | Test coverage |
| --- | --- |
| Boundary issue numbers | Fixture branches `feature/1200-slug`, `feature/12000-slug`, and `feature/foo-1200`; assert only the anchored issue branch matches |
| Branch-prefix lookalikes | Fixture `fix/1200-slug` and `hotfix/1200-slug`; assert prefix classification stays distinct |
| Existing canonical artifact | Expected branch fixture returns `RESULT=clean` with canonical artifact detail |
| Duplicate local worktree | Fixture duplicate worktree returns `RESULT=blocked_duplicate` and discovered path |
| Remote branch without local worktree | Mocked `git ls-remote` result returns `RESULT=blocked_duplicate` |
| Open PR wrong base | Mocked `gh pr list` JSON with `baseRefName: main` returns `RESULT=wrong_base` |
| Missing base | Empty `--approved-base` in `pre-pr` returns `RESULT=missing_base` |
| Deliberate split path | Same duplicate fixture with `--allow-split true` and approved base returns `RESULT=clean` plus split audit detail |
| Multiple artifacts in one scan | Fixture with branch and PR emits both artifact identifiers |
| Empty command output | Empty fixtures return `RESULT=clean` |
| CLI/API failure | Mocked non-zero `git` or `gh` returns a non-clean result and required action |

### Suppression Semantics

No inline suppression directives are part of this feature. ShellCheck
suppressions should follow `docs/best-practices/1-general.md` if implementation
discovers an unavoidable false positive.

---

## Cross-Cutting Checklist Plan

This plan modifies a cross-cutting workflow safety category because it adds a
pre-mutation duplicate/base guard that applies across spec, plan, implementation,
single-item orchestration, batch orchestration, and epic orchestration.

Required implementation coverage:

- Developer protocol and guidance: `03-implement-development-protocol.md`,
  `.claude/agents/developer.md`, `.cursor/agents/developer.md`, and
  `.codex/skills/workflow-implementer/SKILL.md`.
- Planning protocol and guidance: `02-generate-implementation-plan-protocol.md`,
  `.claude/agents/tech-lead.md`, `.cursor/agents/tech-lead.md`, and
  `.codex/skills/workflow-plan-writer/SKILL.md`.
- Spec protocol and guidance: `01-generate-spec-protocol.md`,
  `.claude/agents/product-manager.md`, `.cursor/agents/product-manager.md`, and
  `.codex/skills/workflow-spec-writer/SKILL.md`.
- Orchestration protocols and guidance: `90-batch-orchestrate-work-protocol.md`,
  `91-orchestrate-work-protocol.md`, `95-run-epic-protocol.md`,
  `.claude/agents/orchestrator.md`, `.cursor/agents/orchestrator.md`,
  `.claude/agents/item-orchestrator.md`, `.cursor/agents/item-orchestrator.md`,
  `.codex/skills/workflow-orchestrator/SKILL.md`, and
  `.codex/skills/workflow-item-orchestrator/SKILL.md`.
- Command-style aliases: `.agents/skills/run-work/SKILL.md`,
  `.agents/skills/run-items/SKILL.md`, `.agents/skills/run-item/SKILL.md`,
  `.agents/skills/run-item-work/SKILL.md`, and
  `.agents/skills/run-epic/SKILL.md`.
- Review contract: `REVIEW.md`.

---

## Testing Strategy

**Test types**: Shell unit tests, workflow guard lint, markdown lint, smoke/manual.

**Key scenarios to test**:

1. Nested duplicate artifact is blocked before creation - maps to AC1 and AC2.
2. Missing base and wrong base refuse branch or PR creation - maps to AC3, AC4,
   AC5, and AC6.
3. Parent audit detects unexpected worktrees and PRs during orchestration - maps
   to AC7, AC8, AC9, and AC10.
4. Deliberate split work requires explicit approval and base context - maps to
   AC11.
5. Smoke/regression coverage exercises duplicate, missing-base, wrong-base, and
   parent-warning paths - maps to AC12.

**Smoke test runbook**:
`docs/testing/workflow/1200-prevent-unsanctioned-nested-agent-prs.smoke-test.md`

**Regression suite**:

- Add `scripts/development-workflow/tests/test-run-nested-artifact-guard.sh`.
- Add the new test to whichever workflow test aggregator or CI path currently
  runs `scripts/development-workflow/tests/test-*.sh`. If there is no
  aggregator, document the direct command in the implementation PR verification.

---

## Seed Data

No application seed data is required. Shell tests should create temporary git
fixtures and mocked `gh` output under `mktemp -d` paths, then clean them up.

---

## Documentation Updates

- [ ] `docs/workflow/development-workflow/protocols/01-generate-spec-protocol.md`
      - add base-context refusal before spec branch and PR creation.
- [ ] `docs/workflow/development-workflow/protocols/02-generate-implementation-plan-protocol.md`
      - add base-context refusal before plan branch and PR creation.
- [ ] `docs/workflow/development-workflow/protocols/03-implement-development-protocol.md`
      - add duplicate/base guard before implementation branch, commit, push, and
      PR creation.
- [ ] `docs/workflow/development-workflow/protocols/90-batch-orchestrate-work-protocol.md`
      - add parent audit checkpoints and explicit-list fork reporting.
- [ ] `docs/workflow/development-workflow/protocols/91-orchestrate-work-protocol.md`
      - add guard calls and summary reporting for item runners.
- [ ] `docs/workflow/development-workflow/protocols/95-run-epic-protocol.md`
      - add guard calls for epic delegated dispatch.
- [ ] `scripts/development-workflow/README.md` - document the new helper.
- [ ] `REVIEW.md` - document review expectations for duplicate/base guards.
- [ ] `AGENTS.md` - none; repository-level branch and PR conventions are already
      correct and this implementation affects internal workflow protocols.

---

## Risks & Mitigations

| Risk | Likelihood | Impact | Mitigation |
| --- | --- | --- | --- |
| Required runner surface is missed | Medium | High | Use the cross-cutting target search from the Verification Log and update every listed agent/skill/protocol surface |
| Guard false-positives on similarly numbered branches | Medium | Medium | Anchor branch and issue matching and cover boundary cases in shell tests |
| Guard blocks legitimate split work | Low | Medium | Add explicit split-approval and approved-base inputs, and require audit output when used |
| `gh` or network failure is mistaken for clean state | Medium | High | Treat CLI/API failures as non-clean results with required action |
| Documentation and helper result strings drift | Medium | Medium | Verify exact `RESULT=` values against the helper source during implementation review |

---

## Implementation Order

1. Create `scripts/development-workflow/run-nested-artifact-guard.sh` with
   bash 3.2-compatible parsing, structured `RESULT=` output, anchored
   issue-scoped artifact matching, and no silent `git` or `gh` failure fallback.
2. Add `scripts/development-workflow/tests/test-run-nested-artifact-guard.sh`
   covering every parser-risk edge case and acceptance criterion path listed in
   **Parser-Risk Addendum**.
3. Update `scripts/development-workflow/open-product-pr.sh` so empty or
   conflicting base context is rejected before `gh pr create`.
4. Update Protocols 90, 91, and 95 to call the guard at parent checkpoints and
   to include duplicate-fork stops or warnings in parent-visible summaries.
5. Update Protocols 01, 02, and 03 so stage agents refuse branch or PR creation
   when base context is missing, ambiguous, or inconsistent with the parent run.
6. Update all agent and skill guidance listed in **Files to Modify**, preserving
   mirrored Claude/Cursor/Codex behavior and command-style alias parity.
7. Update `REVIEW.md` with blocking review checks for missing duplicate/base
   guard coverage and unintended default-branch fallback.
8. Update `scripts/development-workflow/README.md` with helper usage, modes,
   inputs, outputs, and caller expectations.
9. Update `CHANGELOG.md` under `[Unreleased]` using this literal entry:
   `- **Prevent unsanctioned nested agent PRs** (#1200): Add workflow guards that stop duplicate nested-agent artifacts and reject missing or wrong PR base context.`
10. Run shell verification:
    `bash scripts/development-workflow/tests/test-run-nested-artifact-guard.sh`.
11. Run workflow shell verification:
    `shellcheck --severity=warning scripts/development-workflow/run-nested-artifact-guard.sh scripts/development-workflow/open-product-pr.sh scripts/development-workflow/tests/test-run-nested-artifact-guard.sh`
    and
    `python3 scripts/lint/workflow-shell-guard-lint.py --base-ref origin/develop`.
12. Run markdown verification:
    `npx markdownlint-cli2 "docs/workflow/development-workflow/protocols/*.md" "docs/testing/workflow/*.md" "CHANGELOG.md"`.
13. Execute the smoke test runbook and confirm it covers duplicate-artifact
    detection, missing-base refusal, wrong-base refusal, parent-visible fork
    warnings, and deliberate split approval.
