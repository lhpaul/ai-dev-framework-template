# Delete Remote Implementation Branch After Multi-Stage Merge - Implementation Plan

**Spec**: [1_1185-delete-remote-implementation-branch-after-merge_specs.md](./1_1185-delete-remote-implementation-branch-after-merge_specs.md)
**Smoke test runbook**: [1185-delete-remote-implementation-branch-after-merge.smoke-test.md](../../../testing/workflow/1185-delete-remote-implementation-branch-after-merge.smoke-test.md)

---

## Summary

**Approach**: Make implementation-branch remote cleanup an explicit
post-merge invariant in the item cleanup path, then teach stale-branch scan
guidance to categorize workflow branches by lifecycle before warning. Reuse the
existing MERGED-state guard from `batch-merge.sh delete-branch` semantics so
remote deletion is attempted only after a merged PR is confirmed, and report
`deleted`, `already absent`, `expected persistent`, `skipped`, or `failed`
without implying cleanup succeeded when it did not.

**Estimated complexity**: M

**Rationale**: The change is shell workflow logic with GitHub CLI integration,
structured output, and branch-name classification edge cases. It touches shared
workflow cleanup and orchestration documentation, so focused tests are required
to prevent regressions in both single-stage and multi-stage paths.

**Dependencies**: None.

---

## Verification Log

| Check | Command / query | Result |
| --- | --- | --- |
| Repo revision | `git rev-parse --short HEAD` | `38829f7` |
| Template-fit check | `rg -n "template:\|is_template: true" .ai-dev-workflow.yaml` | Template repo confirmed; spec is generic workflow tooling. |
| Issue status | `gh issue view 1185 --json number,title,state,projectItems` | Issue `#1185` is open and in Project status `Writing Plan`. |
| Existing remote-delete primitive | `rg -l "delete-branch\|DELETE_RESULT\|git push origin --delete" scripts/development-workflow docs/workflow .codex .claude .cursor .agents \| sort` | 7 files reference remote branch deletion; primary reusable behavior is `scripts/development-workflow/batch-merge.sh delete-branch`. |
| Cleanup status mapping | `rg -n "Spec Ready\|Plan Ready\|Merged\|post-merge-cleanup" scripts/development-workflow/post-merge-cleanup.sh docs/workflow/development-workflow/protocols/91-orchestrate-work-protocol.md` | `post-merge-cleanup.sh` maps spec to `Spec Ready`, plan to `Plan Ready`, and implementation branches to `Merged`; Protocol 91 Step 10 points all post-merge cleanup through this helper. |
| Stale scan lifecycle guidance | Review Protocol 90's stale workflow branch check in `docs/workflow/development-workflow/protocols/90-batch-orchestrate-work-protocol.md`. | Protocol 90 Check 3 currently groups spec, plan, and implementation branches together as stale local branches; it needs lifecycle-category output. |
| Existing test surface | `rg -l "delete-branch\|post-merge-cleanup\|workflow-next-action\|workflow-batch-plan\|branch.*feature/\|implementation-plan" scripts/development-workflow/tests \| sort` | Reuse shell tests under `scripts/development-workflow/tests/`, especially batch merge, tracker merge mapping, and item completion self-check tests. |

---

## Layer-by-Layer Changes

### Workflow Shell Helpers

- [ ] Update `scripts/development-workflow/post-merge-cleanup.sh` so
      `feature/*`, `fix/*`, `refactor/*`, and `hotfix/*` branches perform a
      guarded remote-branch cleanup after a merged PR is confirmed and before
      cleanup is reported complete. Maps to AC1, AC2, AC3, AC4, and AC8.
- [ ] Preserve existing tracker and issue closeout behavior in
      `post-merge-cleanup.sh`: spec branches still transition to `Spec Ready`,
      implementation-plan branches still transition to `Plan Ready`, and
      implementation branches still transition to `Merged`. Maps to AC2 and
      AC5.
- [ ] Share or mirror the output categories from `batch-merge.sh delete-branch`
      so both single-stage batch merges and multi-stage terminal cleanup expose
      equivalent results: deleted, already absent, skipped because PR is not
      merged, and failed because deletion could not be verified. Maps to AC2,
      AC4, and AC8.
- [ ] Ensure cleanup failure is terminal for the current cleanup claim: if an
      implementation branch still exists remotely after a confirmed merged PR
      and deletion fails for auth, network, or permission reasons, the script
      exits non-zero and prints the affected branch plus PR number. Maps to AC6,
      AC7, and AC8.

### Portfolio Scan / Audit Guidance

- [ ] Update Protocol 90 Check 3 in
      `docs/workflow/development-workflow/protocols/90-batch-orchestrate-work-protocol.md`
      to audit both local workflow branches and remote `origin/*`
      implementation refs, then classify workflow branches by lifecycle before
      surfacing findings: spec and implementation-plan branches are
      expected-persistent after merge; implementation branches are
      expected-deleted after merge. Maps to AC5, AC6, and AC7.
- [ ] If a script-backed scan path is updated, emit branch category and merged
      PR context in stable key/value output, for example
      `BRANCH_LIFECYCLE=expected-deleted` or
      `BRANCH_LIFECYCLE=expected-persistent`. Maps to AC6 and AC7.
- [ ] Keep audit or scan behavior read-only. The scan should identify stale
      remote implementation branches and suggest the guarded cleanup path; it
      must not delete branches itself. Maps to AC3 and AC7.

### Orchestration Documentation

- [ ] Update
      `docs/workflow/development-workflow/protocols/91-orchestrate-work-protocol.md`
      Step 10 to make the remote implementation-branch cleanup result part of
      post-merge completion evidence for implementation branches. Maps to AC1,
      AC2, AC4, and AC8.
- [ ] Update
      `docs/workflow/development-workflow/protocols/94-batch-merge-protocol.md`
      only if implementation changes alter the caller contract for
      `batch-merge.sh delete-branch` or make `post-merge-cleanup.sh` idempotent
      for remote branch cleanup after `delete-branch` has already run. Maps to
      AC2 and AC4.
- [ ] Update `.codex/skills/post-merge-cleanup/SKILL.md`,
      `.claude/skills/post-merge-cleanup.md`,
      `.claude/commands/post-merge-cleanup.md`, and
      `.cursor/commands/post-merge-cleanup.md` if the user-facing cleanup
      contract changes from "remote branch already deleted" to "helper verifies
      or performs guarded remote deletion for implementation branches." Maps to
      AC1, AC2, and AC8.

### Files to modify

```text
scripts/development-workflow/post-merge-cleanup.sh
scripts/development-workflow/tests/test-post-merge-cleanup.sh
scripts/development-workflow/tests/test-batch-merge-checkpoints.sh
docs/workflow/development-workflow/protocols/90-batch-orchestrate-work-protocol.md
docs/workflow/development-workflow/protocols/91-orchestrate-work-protocol.md
docs/workflow/development-workflow/protocols/94-batch-merge-protocol.md
.codex/skills/post-merge-cleanup/SKILL.md
.claude/skills/post-merge-cleanup.md
.claude/commands/post-merge-cleanup.md
.cursor/commands/post-merge-cleanup.md
docs/testing/workflow/1185-delete-remote-implementation-branch-after-merge.smoke-test.md
CHANGELOG.md
```

`docs/workflow/development-workflow/protocols/94-batch-merge-protocol.md` and
the command/skill files are conditional implementation targets: update them
only when the `post-merge-cleanup.sh` caller contract changes. `CHANGELOG.md`
is listed for the later implementation PR only; this plan PR must not modify it.

---

## Testing Strategy

**Test types**: Shell unit tests, protocol/document lint, and smoke/manual audit.

**Key scenarios to test**:

1. Multi-stage implementation cleanup: a merged `feature/1185-slug` PR leaves
   `origin/feature/1185-slug`; running `post-merge-cleanup.sh --base develop`
   deletes the remote branch and reports the deletion. Maps to AC1, AC2, AC3,
   AC6, AC7, AC8, and AC9.
2. Already absent remote branch: a merged implementation PR whose remote branch
   is gone reports already complete and continues tracker/local cleanup. Maps
   to AC4 and AC9.
3. Unmerged implementation PR: cleanup sees an open or closed-but-not-merged PR
   and refuses remote deletion. Maps to AC3 and AC9.
4. Spec and plan branch lifecycle: merged `spec/*` and
   `implementation-plan/*` branches are classified as expected-persistent and
   are not treated as implementation cleanup failures. Maps to AC5, AC7, and
   AC9.
5. Deletion failure: `git push origin --delete` fails for an implementation
   branch after merge verification; cleanup reports failure and exits non-zero
   instead of producing a successful terminal summary. Maps to AC8 and AC9.

**Smoke test runbook**:
`docs/testing/workflow/1185-delete-remote-implementation-branch-after-merge.smoke-test.md`

**Regression suite**: Add or update shell tests under
`scripts/development-workflow/tests/`. Prefer a dedicated
`test-post-merge-cleanup.sh` if it exists or is created; otherwise add focused
branch-deletion cases to the closest existing cleanup test file and keep
`test-batch-merge-checkpoints.sh` coverage for the existing
`batch-merge.sh delete-branch` contract.

### Parser-risk addendum

This plan is parser-risk because the implementation classifies structured
branch names and scans GitHub/remote branch state.

**Edge-case enumeration**:

- Boundary prefix matches: `feature/1185-slug`, `fix/1185-slug`,
  `refactor/1185-slug`, and `hotfix/1185-slug` are implementation branches;
  `spec/1185-slug` and `implementation-plan/1185-slug` are not.
- Numeric boundary negatives: `feature/11850-slug` and
  `feature/21185-slug` must not match issue `1185` cleanup/audit queries.
- Tracker-prefixed branches: `feature/ENG-1185-slug` and
  `fix/RAD-1185-slug` are implementation branches and should preserve their
  full branch names while extracting the numeric GitHub issue only where
  existing tracker helpers require it.
- Lookalike text: `docs/feature/1185-slug.md`, `my-feature/1185-slug`, and
  `implementation-plan-extra/1185-slug` must not be classified as workflow
  implementation branches.
- Already absent remote: Git reports `remote ref does not exist`; cleanup must
  report already complete, not failure.
- Merged-state guard: PR states `OPEN` and `CLOSED` must both skip remote
  deletion; only `MERGED` allows deletion.
- Multiple branches for one issue: if both a spec/plan branch and an
  implementation branch exist for the issue, scan output must identify their
  separate lifecycle categories instead of producing one ambiguous stale
  warning.

**Unit test mapping**:

- `scripts/development-workflow/tests/test-post-merge-cleanup.sh`:
  merged implementation branch deletes remote, already absent remote is
  successful, unmerged PR skips deletion, deletion failure exits non-zero,
  branch-prefix boundary cases, and team-prefixed implementation branches.
- `scripts/development-workflow/tests/test-batch-merge-checkpoints.sh`:
  retain and, if needed, extend `batch-merge.sh delete-branch` tests for
  `MERGED` guard parity and `DELETE_RESULT` categories.
- `scripts/development-workflow/tests/test-workflow-batch-plan.sh` or a new
  focused audit test: spec/plan branches are expected-persistent while merged
  implementation branches with remote refs are expected-deleted findings.

**Suppression semantics**: Not applicable; this feature does not introduce
inline suppressions.

### Concurrent-event-source addendum

Not applicable. The feature does not introduce concurrent listeners, timers,
queues, or shared mutable state across asynchronous execution contexts.

---

## Seed Data

No application seed data is required. Shell tests should create temporary git
repositories and mock `gh`/`git push` behavior with deterministic fixture data:

| Entity | Values / Scenario | File |
| --- | --- | --- |
| Mock merged PR | `number=1185`, `state=MERGED`, `headRefName=feature/1185-delete-remote-implementation-branch-after-merge` | Temporary fixture in shell test |
| Mock unmerged PR | `state=OPEN` and `state=CLOSED` for the same implementation branch | Temporary fixture in shell test |
| Mock persistent branches | `spec/1185-delete-remote-implementation-branch-after-merge` and `implementation-plan/1185-delete-remote-implementation-branch-after-merge` | Temporary fixture in shell test |

---

## Documentation Updates

- [ ] `docs/workflow/development-workflow/protocols/90-batch-orchestrate-work-protocol.md`
      - document expected-persistent versus expected-deleted branch categories
      in stale-branch scan/audit output.
- [ ] `docs/workflow/development-workflow/protocols/91-orchestrate-work-protocol.md`
      - require implementation remote-branch cleanup evidence before reporting
      post-merge cleanup complete.
- [ ] `docs/workflow/development-workflow/protocols/94-batch-merge-protocol.md`
      - update only if the implementation changes the relationship between
      `batch-merge.sh delete-branch` and `post-merge-cleanup.sh`.
- [ ] `.codex/skills/post-merge-cleanup/SKILL.md`,
      `.claude/skills/post-merge-cleanup.md`,
      `.claude/commands/post-merge-cleanup.md`, and
      `.cursor/commands/post-merge-cleanup.md` - update if the cleanup helper
      now verifies or performs guarded remote deletion directly.

---

## Risks & Mitigations

| Risk | Likelihood | Impact | Mitigation |
| --- | --- | --- | --- |
| Remote branch deletion runs before GitHub confirms merge | Low | High | Keep the existing `MERGED`-state guard as the enforcement mechanism and test `OPEN`/`CLOSED` states. |
| Spec or implementation-plan branches are incorrectly reported as cleanup failures | Medium | Medium | Use explicit branch lifecycle classification and tests for both prefixes. |
| Cleanup succeeds locally while remote deletion failed | Medium | High | Treat remote deletion failure for implementation branches as non-terminal cleanup and exit non-zero with branch and PR context. |
| Duplicate deletion between `batch-merge.sh delete-branch` and `post-merge-cleanup.sh` causes false failures | Medium | Medium | Interpret "remote ref does not exist" as already complete and keep that idempotency covered by tests. |
| Broad issue-number branch matching catches unrelated branches | Medium | Medium | Use prefix-aware branch matching and numeric boundary tests. |

---

## Implementation Order

1. Add the branch lifecycle helpers or local functions needed by
   `post-merge-cleanup.sh` to distinguish implementation branches from
   expected-persistent spec/plan branches.
2. In `post-merge-cleanup.sh`, resolve the merged PR for implementation
   branches before remote deletion, using the same merged-state guarantee that
   `batch-merge.sh delete-branch` enforces. Do not delete if the PR is not
   confirmed `MERGED`.
3. Add guarded remote branch deletion for implementation branches. Report
   deleted, already absent, skipped, or failed with the affected branch and PR
   number. Preserve existing local branch, worktree, tracker, and issue closeout
   behavior after successful or already-complete remote cleanup.
4. Update Protocol 90 stale-branch scan guidance so scan/audit output shows
   branch lifecycle category and merged PR context, and so spec/plan branches
   are expected-persistent while implementation branches are expected-deleted.
5. Update Protocol 91 Step 10 so implementation post-merge completion requires
   remote branch cleanup evidence in addition to local branch, worktree, and
   tracker verification.
6. Update Protocol 94 and post-merge cleanup skill/command guidance only if the
   helper contract changed. Keep all documentation consistent about which
   branch prefixes are implementation branches.
7. Add shell tests for the parser-risk edge cases and cleanup result categories
   listed in the Testing Strategy. Keep tests deterministic with temporary
   repos and mocked `gh`/`git push`.
8. Run targeted verification:
   `bash scripts/development-workflow/tests/test-post-merge-cleanup.sh`,
   `bash scripts/development-workflow/tests/test-batch-merge-checkpoints.sh`,
   and any updated workflow scan/audit test.
9. Run broad workflow verification appropriate for shell changes:
   `python3 scripts/lint/workflow-shell-guard-lint.py --base-ref origin/develop`
   if shell guard lint exists in the checkout, markdown lint for changed docs,
   and ShellCheck or the repository's shell CI-equivalent when available.
10. Update `docs/testing/workflow/1185-delete-remote-implementation-branch-after-merge.smoke-test.md`
    if implementation details change the manual audit procedure.
11. Update `CHANGELOG.md` under `[Unreleased]` in the implementation PR with:
    `- **Delete remote implementation branches after merge** (#1185): Ensure multi-stage item cleanup deletes merged implementation branches while treating spec and plan branches as expected-persistent.`

---

## Residual Verification Strategy

Before the implementation PR can be marked `ready-for-human-review`, the
developer must provide residual evidence from the test logs showing:

- Merged implementation remote branch deletion succeeds.
- Already absent implementation remote branches are successful/idempotent.
- Unmerged implementation PRs do not delete remote branches.
- Spec and implementation-plan branches are categorized as expected-persistent.
- A deletion failure remains visible and blocks a successful cleanup claim.
