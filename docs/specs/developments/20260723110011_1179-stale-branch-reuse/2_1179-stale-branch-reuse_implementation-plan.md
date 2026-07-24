# Validate Existing Workflow Branches Before Reuse - Implementation Plan

**Spec**: [1_1179-stale-branch-reuse_specs.md](1_1179-stale-branch-reuse_specs.md)
**Smoke test runbook**: [1179-stale-branch-reuse.smoke-test.md](../../../testing/workflow/1179-stale-branch-reuse.smoke-test.md)

---

## Summary

**Approach**: Add a read-only branch-reuse validator between existing-branch
discovery and the normal `/run-item` resume path. The validator will resolve the
approved base and discovered branch tip from explicit inputs, require positive
ancestry evidence before returning `compatible`, report local-versus-remote
divergence as a separate diagnostic, and fail closed without changing Git,
tracker, or PR state when the evidence is incompatible or unavailable.

**Estimated complexity**: M

**Rationale**: The Git operation is compact, but this is a workflow safety gate
that must behave consistently across local, remote-only, and worktree-owned
branches. It therefore requires a dedicated helper, fixture-based shell tests,
Protocol 91 integration, and aligned command/agent/skill guidance.

**Dependencies**: None.

---

## Verification Log

| Check | Command / query | Result |
| --- | --- | --- |
| Repo revision | `git rev-parse --short HEAD` | `21f23e3` |
| Template-fit check | Read `.ai-dev-workflow.yaml`, issue #1179, and the approved spec | `template.is_template: true`; the item is reusable workflow safety tooling |
| Current resume behavior | `rg -n "Pre-dispatch branch check\|workflow-next-action.sh" docs/workflow/development-workflow/protocols/91-orchestrate-work-protocol.md` | Protocol 91 currently resumes any matching local, remote, or worktree branch without validating ancestry |
| Existing artifact guard | Read `scripts/development-workflow/run-nested-artifact-guard.sh` and its test harness | The guard detects duplicate topology and base/worktree placement; it does not prove that a reusable branch contains the approved base |
| Supported runner surfaces | `rg -l "run-nested-artifact-guard.sh\|workflow-next-action.sh" .agents/skills/run-item/SKILL.md .codex/skills/workflow-item-orchestrator/SKILL.md .claude/agents/item-orchestrator.md .cursor/agents/item-orchestrator.md .claude/commands/run-item.md .cursor/commands/run-item.md` | Protocol-backed Codex, Claude, and Cursor item-runner surfaces must preserve the same branch-reuse gate |
| Existing test patterns | `find scripts/development-workflow/tests -maxdepth 1 -type f \( -name '*branch*' -o -name '*worktree*' -o -name '*nested*' \) -print` | Reuse the self-contained temporary-repository style used by the nested-artifact and worktree-resume harnesses |
| Current development artifacts | `find docs/specs/developments/20260723110011_1179-stale-branch-reuse -maxdepth 1 -type f -print` | The approved spec exists; this PR adds the plan and smoke runbook |

---

## Layer-by-Layer Changes

### Workflow Scripts

- [ ] Add `scripts/development-workflow/validate-branch-reuse.sh` as a
      read-only, fail-closed validator.
- [ ] Require explicit `--issue`, `--branch`, `--approved-base`, and
      `--repo-root` inputs. Accept an optional remote name that defaults to
      `origin`, but never infer a different approved base from repository
      defaults or tracking configuration.
- [ ] Resolve branch evidence across local refs, remote-tracking refs, and
      registered worktrees. When both local and remote tips exist, use the
      local/worktree tip as the candidate work tip and retain the remote tip
      only for divergence diagnostics.
- [ ] Resolve the approved base deterministically from its remote-tracking ref
      when available, otherwise from an unambiguous local ref. Report the exact
      resolved ref and object ID used for the decision.
- [ ] Require `git merge-base --is-ancestor <approved-base-tip>
      <candidate-branch-tip>` to succeed before returning `compatible`.
- [ ] Return distinct structured results for `no_existing_branch`,
      `compatible`, `incompatible`, and `verification_blocked`. Reserve a
      separate non-zero usage/error outcome for invalid invocation.
- [ ] Emit stable `KEY=value` output for shell callers and support `--json` for
      deterministic automation and tests. Include item, branch, approved base,
      resolved refs/tips, result, reason, divergence evidence, and human action.
- [ ] Calculate local-versus-remote ahead/behind counts only when both refs
      resolve. Do not use those counts as approved-base compatibility evidence.
- [ ] Keep the helper strictly read-only: no fetch, checkout, switch, branch
      creation/deletion, reset, rebase, push, PR, label, or tracker mutation.
      Callers remain responsible for refreshing refs before invoking it.
- [ ] Provide recovery guidance for every blocked result without attempting
      destructive recovery.

### Work Item Runner Protocol

- [ ] Update the Protocol 91 pre-dispatch branch check to invoke
      `validate-branch-reuse.sh` whenever branch discovery finds a candidate.
- [ ] Run the new validator after the bounded prelude has established
      `BASE_BRANCH` and after the nested-artifact topology check has confirmed
      that the candidate is the canonical artifact.
- [ ] Permit `workflow-next-action.sh --branch <branch>` only when the validator
      returns `compatible`.
- [ ] Preserve the existing fresh-branch dispatch when the discovery and
      validator result is `no_existing_branch`.
- [ ] Stop before creator dispatch, tracker mutation, PR mutation, or Git
      mutation on `incompatible` or `verification_blocked`.
- [ ] Distinguish confirmed incompatible ancestry from unavailable or ambiguous
      evidence in both operator output and the Work Item Runner summary.
- [ ] Require the final summary to record one of `fresh_branch`,
      `compatible_reuse`, `incompatible_reuse_blocked`, or
      `reuse_verification_blocked`.
- [ ] State that automatic delete, reset, rebase, checkout, or force-push is
      forbidden recovery behavior. Human approval must remain explicit for any
      later destructive or history-rewriting action.
- [ ] Preserve the nested-artifact guard, worktree isolation, approved-base
      resolution, checkpoint-resume preflight, and integration-branch override
      gates as independent checks.

### Agent, Skill, and Command Guidance

- [ ] Update `.agents/skills/run-item/SKILL.md` to require positive approved-base
      ancestry evidence before any existing branch is reused.
- [ ] Update `.codex/skills/workflow-item-orchestrator/SKILL.md` with the same
      pre-resume gate and blocked-result behavior.
- [ ] Update `.claude/agents/item-orchestrator.md` and
      `.cursor/agents/item-orchestrator.md` so internal handoffs cannot treat a
      matching item number as sufficient evidence.
- [ ] Update `.claude/commands/run-item.md` and `.cursor/commands/run-item.md`
      with concise user-facing responsibilities for safe existing-branch reuse.
- [ ] Leave deprecated `/run-item-work` aliases unchanged because they delegate
      to the canonical `/run-item` surface rather than defining independent
      branch-reuse behavior.

### Tests

- [ ] Add
      `scripts/development-workflow/tests/test-validate-branch-reuse.sh`.
- [ ] Build disposable Git repositories and remotes inside a temporary
      directory so ancestry and divergence assertions use real Git history.
- [ ] Cover no existing branch, compatible local branch, compatible remote-only
      branch, and compatible worktree-owned branch.
- [ ] Cover an item-matching branch whose history does not contain the approved
      base.
- [ ] Cover a compatible local branch with a stale remote-tracking ref and
      assert that divergence is diagnostic rather than blocking.
- [ ] Cover missing approved base, missing/ambiguous candidate refs, and an
      injected failed ancestry query.
- [ ] Assert the helper never changes checked-out branch, refs, worktree
      registrations, working-tree files, or repository status.
- [ ] Assert both stable shell output and `--json` expose the same decision,
      reason, evidence, and human action.
- [ ] Run the existing nested-artifact guard and worktree-resume tests as
      regressions because the new gate composes with those paths.

### Database / Data Layer

- [ ] Not applicable. No schema, migration, seed, or persistent product data is
      changed.

### Backend / API

- [ ] Not applicable. No product service or API behavior is changed.

### Shared Packages / Libraries

- [ ] Not applicable. The shared implementation surface is shell workflow
      tooling and protocol documentation.

### Frontend / UI

- [ ] Not applicable. There is no product UI.

### Infrastructure / Configuration

- [ ] No secrets, deployment resources, or third-party services are required.
- [ ] The helper depends only on Git and the repository's existing shell/JSON
      conventions. If JSON rendering uses `jq`, follow the repository's current
      dependency checks and fail with a clear infrastructure message when it is
      unavailable.

---

## Files to Modify

### Required Implementation Files

- [ ] `scripts/development-workflow/validate-branch-reuse.sh` - new read-only
      branch compatibility validator.
- [ ] `scripts/development-workflow/tests/test-validate-branch-reuse.sh` - new
      temporary-repository shell test harness.
- [ ] `docs/workflow/development-workflow/protocols/91-orchestrate-work-protocol.md`
      - canonical placement, result routing, stops, and summary behavior.
- [ ] `.agents/skills/run-item/SKILL.md` - command-style Codex runner gate.
- [ ] `.codex/skills/workflow-item-orchestrator/SKILL.md` - canonical Codex
      item-orchestrator gate.
- [ ] `.claude/agents/item-orchestrator.md` - Claude internal runner behavior.
- [ ] `.cursor/agents/item-orchestrator.md` - Cursor internal runner behavior.
- [ ] `.claude/commands/run-item.md` - Claude user-facing command guidance.
- [ ] `.cursor/commands/run-item.md` - Cursor user-facing command guidance.

### Explicitly Not Required

- [ ] `scripts/development-workflow/run-nested-artifact-guard.sh` is not
      extended. Duplicate-artifact topology and branch ancestry are separate
      decisions and should remain independently testable.
- [ ] `scripts/development-workflow/workflow-next-action.sh` is not changed. It
      runs only after the new gate authorizes branch reuse.
- [ ] Deprecated `/run-item-work` aliases are not changed because they delegate
      to the canonical command.
- [ ] `CHANGELOG.md` is not modified by this plan PR. The later implementation
      PR adds the exact entry listed in **Implementation Order**.
- [ ] Product application files and `docs/project/*` are outside this
      workflow-template change.

---

## Decision-Gate Consistency Matrix

| Gate inputs | Allowed outcome | Required next action | Mirror surfaces | Test coverage |
| --- | --- | --- | --- | --- |
| No item-matching branch exists and approved base resolves | `fresh_branch` | Continue normal creator dispatch from approved base | Protocol 91; item-orchestrator agents/skills; `/run-item` commands | `no_existing_branch_uses_fresh_path` |
| Local item branch contains approved-base tip | `compatible_reuse` | Report evidence and call `workflow-next-action.sh` | Same runner surfaces; validator output | `compatible_local_branch_resumes` |
| Remote-only item branch contains approved-base tip | `compatible_reuse` | Resume the canonical remote branch path without creating a duplicate | Same runner surfaces; validator output | `compatible_remote_only_branch_resumes` |
| Registered-worktree item branch contains approved-base tip | `compatible_reuse` | Preserve the worktree owner and resume there | Same runner surfaces; isolation guidance | `compatible_worktree_branch_resumes` |
| Candidate branch does not contain approved-base tip | `incompatible_reuse_blocked` | Stop before mutation; report evidence and human recovery | Protocol 91; all item-runner surfaces | `incompatible_base_blocks` |
| Approved base, candidate tip, or ancestry query cannot be resolved unambiguously | `reuse_verification_blocked` | Stop before mutation; restore evidence and retry or request human decision | Protocol 91; all item-runner surfaces | `missing_base_blocks`, `ambiguous_ref_blocks`, `ancestry_query_failure_blocks` |
| Local candidate is compatible but differs from its remote-tracking ref | `compatible_reuse` plus divergence diagnostic | Resume from approved-base evidence and report ahead/behind separately | Validator output; Protocol 91 summary | `stale_tracking_ref_is_diagnostic` |

---

## Cross-Cutting Checklist Coverage

This plan does not introduce a new checklist category that applies to every
implementation. It adds one bounded decision gate to existing-branch reuse.
Cross-surface completeness is nevertheless mandatory:

- [ ] Protocol coverage: Protocol 91 owns discovery, validation ordering,
      branch resume, blocking, and final summary semantics.
- [ ] Agent coverage: Claude and Cursor item-orchestrator agents mirror the
      canonical stop/continue outcomes.
- [ ] Skill coverage: canonical and command-style Codex item-runner skills
      require the validator before resuming.
- [ ] Command coverage: Claude and Cursor `/run-item` descriptions expose the
      same operator-facing safety rule.
- [ ] Test coverage: each consistency-matrix row maps to a named test case.
- [ ] Alias coverage: deprecated aliases are verified to delegate; they do not
      duplicate or weaken the gate.

---

## Parser-Risk Addendum

The helper is parser-risk because it discovers and resolves Git refs, parses
worktree/ref state, and emits machine-readable shell and JSON results.

### Edge-Case Enumeration

1. Exact branch locations:
   - `refs/heads/implementation-plan/1179-stale-branch-reuse`
   - `refs/remotes/origin/implementation-plan/1179-stale-branch-reuse`
   - the same branch checked out in a linked worktree
2. Ref lookalikes:
   - `implementation-plan/11790-stale-branch-reuse`
   - `backup/implementation-plan/1179-stale-branch-reuse`
   - a tag with the expected branch text
3. Approved-base locations:
   - `refs/remotes/origin/develop`
   - unambiguous `refs/heads/develop` when the remote ref is absent
   - missing or ambiguous approved-base ref
4. History shapes:
   - candidate equals approved-base tip
   - candidate is ahead of approved base
   - candidate is unrelated to approved base
   - approved base advanced beyond an older branch point
5. Local/remote divergence:
   - equal tips
   - local ahead
   - local behind
   - diverged
   - remote-tracking ref absent
6. Query failures:
   - invalid repository root
   - candidate ref disappears during validation
   - injected `merge-base` failure
7. Output safety:
   - branch or path containing spaces
   - reason/human-action strings escaped correctly in JSON
   - no partial success result after a failed query

### Unit Test Mapping

Create `scripts/development-workflow/tests/test-validate-branch-reuse.sh`
with at least these cases:

1. `no_existing_branch_uses_fresh_path` covers Edge cases 1 and 2.
2. `compatible_local_branch_resumes` covers Edge cases 1, 3, and 4.
3. `compatible_remote_only_branch_resumes` covers Edge case 1.
4. `compatible_worktree_branch_resumes` covers Edge case 1.
5. `incompatible_base_blocks` covers Edge case 4.
6. `stale_tracking_ref_is_diagnostic` covers Edge case 5.
7. `missing_base_blocks` and `ambiguous_ref_blocks` cover Edge case 3.
8. `ancestry_query_failure_blocks` covers Edge case 6.
9. `lookalike_refs_do_not_match` covers Edge case 2.
10. `shell_and_json_outputs_agree` covers Edge case 7.
11. `validator_is_read_only` snapshots refs, worktrees, HEAD, and status before
    and after the matrix to enforce the no-mutation contract.

### Suppression Semantics

No inline suppression or automatic bypass is introduced. An incompatible or
unverifiable result stops the run. Any destructive cleanup, history rewrite, or
different recovery path requires a separate explicit human decision under the
existing workflow guardrails.

---

## Concurrency Safety

- **Shared mutable state guards**: The helper is read-only and does not lock or
  mutate refs. It evaluates one repository snapshot per invocation.
- **Re-entrancy / in-flight tracking**: Repeated calls over unchanged refs
  produce the same decision and evidence; no durable in-flight state is needed.
- **Event deduplication**: Not applicable. The helper emits output but does not
  post comments or update external systems.
- **Listener and resource cleanup**: The test harness removes disposable
  repositories and worktrees through a trap.
- **Race conditions at initialization**: Resolve base and candidate object IDs
  before the ancestry query and report `verification_blocked` if a ref cannot
  be resolved.
- **Race conditions at teardown**: Re-check resolved object existence before
  success output so a disappearing ref cannot become a partial success.
- **Error propagation across async boundaries**: Not applicable. Shell exit
  codes and structured output propagate errors synchronously.

---

## Testing Strategy

**Test types**: Disposable-repository shell unit harness, regression shell
tests, protocol self-review, markdown lint, and smoke runbook.

**Key scenarios to test**:

1. Fresh branch path remains available when no branch exists. Maps to AC1 and
   AC2.
2. Compatible local, remote-only, and worktree branches resume without
   duplicates. Maps to AC1, AC3, and AC4.
3. Incompatible ancestry blocks before mutation with clear recovery evidence.
   Maps to AC5, AC7, and AC8.
4. Missing or ambiguous evidence fails closed and remains distinct from a
   confirmed incompatibility. Maps to AC6 and AC7.
5. Stale tracking divergence is diagnostic and does not replace approved-base
   ancestry. Maps to AC9.
6. Existing artifact and isolation gates continue to pass their regressions.
   Maps to AC10.
7. Every supported `/run-item` surface preserves the matrix outcomes. Maps to
   AC12.

**Smoke test runbook**:
`docs/testing/workflow/1179-stale-branch-reuse.smoke-test.md`

**Regression suite**:

- `bash scripts/development-workflow/tests/test-validate-branch-reuse.sh`
- `bash scripts/development-workflow/tests/test-run-nested-artifact-guard.sh`
- `bash scripts/development-workflow/tests/test-worktree-resume-preflight.sh`
- `python3 scripts/lint/workflow-shell-guard-lint.py --base-ref origin/develop`

---

## Seed Data

No database seed data is required.

| Entity | Values / Scenario | File |
| --- | --- | --- |
| Disposable Git repositories | Base commits, candidate branches, bare remote, linked worktree, and divergence histories | Generated by `test-validate-branch-reuse.sh` |

---

## Documentation Updates

- [ ] `docs/workflow/development-workflow/protocols/91-orchestrate-work-protocol.md`
      - document validation ordering, structured results, stop/continue
      behavior, recovery limits, and summary states.
- [ ] `.agents/skills/run-item/SKILL.md` and
      `.codex/skills/workflow-item-orchestrator/SKILL.md` - require positive
      ancestry evidence before resume.
- [ ] `.claude/agents/item-orchestrator.md` and
      `.cursor/agents/item-orchestrator.md` - preserve the same gate for
      internal runner handoffs.
- [ ] `.claude/commands/run-item.md` and `.cursor/commands/run-item.md` - expose
      concise operator-facing responsibilities.
- [ ] `docs/project/*` and `AGENTS.md` - no update required because command
      names, branch naming, architecture, and public workflow tables do not
      change.

---

## Risks & Mitigations

| Risk | Likelihood | Impact | Mitigation |
| --- | --- | --- | --- |
| A stale local or remote ref produces a false compatibility decision | Medium | High | Use explicit ref precedence, report resolved object IDs, and test each discovery location |
| Ahead/behind tracking data is mistaken for approved-base ancestry | Medium | High | Compute divergence separately and make `merge-base --is-ancestor` the only compatibility decision |
| The new gate bypasses or replaces artifact isolation checks | Low | High | Place it after canonical-artifact discovery and keep the existing guards independently required |
| Ambiguous Git failures are reported as safe reuse | Low | High | Fail closed with `verification_blocked` and distinct non-zero exits |
| Supported runner surfaces drift | Medium | Medium | Enumerate every canonical mirror and map all outcomes through the consistency matrix |
| Recovery guidance encourages destructive cleanup | Low | High | Name inspection/removal as human-controlled actions and forbid automatic delete/reset/rebase/force-push |

---

## Code Samples

No code samples are included. The implementation PR should add the helper and
fixture harness directly.

---

## Implementation Order

1. Add `scripts/development-workflow/validate-branch-reuse.sh` with explicit
   inputs, deterministic ref resolution, positive ancestry validation,
   separate divergence diagnostics, structured output, and read-only behavior.
2. Add `scripts/development-workflow/tests/test-validate-branch-reuse.sh` and
   implement the parser-risk and decision-matrix cases.
3. Run the new test harness and correct all ref-resolution or output issues.
4. Update Protocol 91 so candidate discovery and nested-artifact validation
   precede the reuse validator, and only `compatible` reaches
   `workflow-next-action.sh`.
5. Update Codex, Claude, and Cursor item-runner skill/agent/command surfaces
   listed in **Files to Modify**.
6. Add the implementation changelog entry under `[Unreleased]` using this exact
   format:
   `- **Validate Existing Workflow Branches Before Reuse** (#1179): Require positive approved-base ancestry evidence before resuming an existing item branch.`
7. Run the new harness plus nested-artifact and worktree-resume regression
   harnesses.
8. Run ShellCheck and
   `python3 scripts/lint/workflow-shell-guard-lint.py --base-ref origin/develop`.
9. Run markdown lint on changed markdown files.
10. Execute
    `docs/testing/workflow/1179-stale-branch-reuse.smoke-test.md` and record the
    implementation evidence in the PR.
