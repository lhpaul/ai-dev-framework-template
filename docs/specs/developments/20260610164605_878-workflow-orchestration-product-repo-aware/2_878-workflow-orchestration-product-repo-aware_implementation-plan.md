# Workflow Orchestration Product Repository Awareness - Implementation Plan

**Spec**: [1_878-workflow-orchestration-product-repo-aware_specs.md](1_878-workflow-orchestration-product-repo-aware_specs.md)
**Smoke test runbook**: [878-workflow-orchestration-product-repo-aware.smoke-test.md](../../../testing/workflow/878-workflow-orchestration-product-repo-aware.smoke-test.md)

---

## Summary

**Approach**: Thread repository-context resolution through the orchestration
scripts at the boundary where implementation-owned work begins. Keep discovery,
spec, plan, and tracker operations hub-owned, while implementation branch
inspection, implementation PR review, implementation CI, and implementation
cleanup accept a selected product repository and run against that repository.

**Estimated complexity**: L

**Rationale**: This modifies several shared workflow scripts and their output
contracts. The risky parts are preserving existing `single_repo` behavior,
avoiding accidental hub PR inspection for product implementation PRs, and
keeping GitHub Projects status/type operations anchored to the workflow hub.

**Dependencies**: #875 must be merged into `develop-workflow-hub-mode` because
this feature depends on repository-context helpers. #877 is useful for operator
status/sync visibility but is not required for the core orchestration routing.

---

## Verification Log

| Check | Command / query | Result |
| --- | --- | --- |
| Repo revision | `git rev-parse --short HEAD` | `8b30a37` |
| Approved spec | `sed -n '1,360p' docs/specs/developments/20260610164605_878-workflow-orchestration-product-repo-aware/1_878-workflow-orchestration-product-repo-aware_specs.md` | Spec requires product-repo-aware discovery, next-action, batch planning, reviewer loop, CI loop, cleanup, tracker helper anchoring, and tests. |
| Current repository-context helpers | `rg -n "workflow_repository_context\|TARGET_GITHUB_REPO\|TARGET_LOCAL_PATH" scripts/development-workflow/workflow-lib.sh scripts/development-workflow/workflow-config-resolver.py` | #875 exposes mode/context helpers and `TARGET_GITHUB_REPO`, `TARGET_GIT_URL`, `TARGET_LOCAL_PATH`, and default branch values. |
| Current script touchpoints | `rg -n "gh pr\|git -C\|workflow_repository_context\|repo-root\|--repo" scripts/development-workflow/{discover-workflow-state.sh,workflow-next-action.sh,workflow-batch-plan.sh,pr-review-loop.sh,pr-ci-loop.sh,post-merge-cleanup.sh,workflow-lib.sh}` | Candidate scripts still default to the current repository for PR, CI, branch, and cleanup operations. |
| Tracker helper location | `rg -n "gh project item-list\|gh issue list\|update_tracker_status_best_effort" scripts/development-workflow/workflow-lib.sh` | GitHub Projects helper paths are centralized in `workflow-lib.sh` and should stay hub-owned. |
| Existing tests | `find scripts/development-workflow/tests -maxdepth 1 -type f \| sort` | Existing shell harnesses cover config resolver, PR review loop, workflow-lib GitHub Projects, and skeleton behavior. |

---

## Layer-by-Layer Changes

### Backend / Scripts

- [ ] Extend `workflow-config-resolver.py` and `workflow-lib.sh` only as needed
      to support orchestration routing.
      - Add a shell-callable product-repository list helper if #877 has not
        already added it.
      - Add a helper that returns the implementation repository context for a
        work item or explicit `--repo <name>` selector.
      - Add a helper that derives a GitHub `owner/repo` slug from
        `TARGET_GITHUB_REPO` or recognized GitHub `TARGET_GIT_URL` forms.
      - Keep tracker helper defaults pointed at the workflow hub repository.
- [ ] Update `discover-workflow-state.sh`.
      - Add `--repo <name>` and `--repo-root <path>` options.
      - Print resolved workflow mode and selected implementation repository.
      - In `single_repo`, preserve current output and current repository
        inspection.
      - In `workflow_hub`, inspect hub-owned specs, plans, tracker status, and
        workflow branches in the hub, but inspect implementation branches and
        implementation PRs in the selected product repository when selection is
        present.
      - Fail clearly when product implementation inspection is requested but
        selection is missing or ambiguous.
- [ ] Update `workflow-next-action.sh`.
      - Add `--repo <name>` and `--repo-root <path>` options.
      - For development-folder targets, keep spec and plan readiness checks
        hub-owned.
      - For implementation branch and implementation PR checks, resolve the
        selected product repository when in `workflow_hub` mode.
      - Emit stable context lines such as `WORKFLOW_MODE=`,
        `ACTION_REPOSITORY_KIND=hub_owned|product_repo_owned`, and
        `ACTION_REPOSITORY=` so orchestrators can report ownership.
      - Fail before product mutations or product PR inspection when selection is
        missing or ambiguous.
- [ ] Update `workflow-batch-plan.sh`.
      - Accept and pass through `--repo <name>` / `--repo-root <path>` to
        `workflow-next-action.sh`.
      - Include repository ownership fields in each candidate block.
      - Preserve file-conflict and tool-fix behavior for `single_repo`.
      - In `workflow_hub`, treat implementation file sets as product-repository
        paths and hub-owned spec/plan paths as hub paths; do not compare paths
        across different repositories as if they were the same file namespace.
- [ ] Update `pr-review-loop.sh`.
      - Add `--repo <owner/repo>` or `--product-repo <name>` support for
        implementation PRs.
      - Use product repository PR API calls when the target PR is
        product-repository-owned.
      - Keep spec and plan PR behavior in the hub repository.
      - Include the selected repository in stable key/value output and summary
        comments.
      - Preserve existing platform behavior for `single_repo`.
- [ ] Update `pr-ci-loop.sh`.
      - Add `--repo <owner/repo>` or `--product-repo <name>` support.
      - Use `gh pr view --repo <owner/repo>` for product implementation PR
        checks.
      - Include `REPO=<owner/repo>` in output for both hub and product contexts.
- [ ] Update `post-merge-cleanup.sh`.
      - Add `--repo <name>` / `--repo-root <path>` and a resolved local path
        route for product implementation cleanup.
      - For `feature/*`, `fix/*`, `refactor/*`, and `hotfix/*` branches in
        `workflow_hub` mode, clean the selected product repository checkout.
      - For `spec/*` and `implementation-plan/*`, keep cleanup in the hub.
      - Keep tracker updates hub-owned and use the numeric issue mapping from
        the hub repository.
      - Fail closed before branch deletion when repository ownership is
        ambiguous.
- [ ] Audit project status/type helper paths in `workflow-lib.sh`.
      - Keep GitHub Projects reads and updates anchored to the hub repository
        unless an explicit future configuration says otherwise.
      - Add regression coverage proving product repository selection does not
        redirect tracker operations.

### Tests

- [ ] Add
      `scripts/development-workflow/tests/test-workflow-orchestration-product-repo-aware.sh`.
- [ ] Use temporary fixture repositories for one workflow hub and two product
      repositories.
- [ ] Cover:
      - missing mode and explicit `single_repo` preserve current behavior
      - workflow hub with two product repos requires selection for
        implementation PR/branch actions
      - selected product repository appears in next-action and discovery output
      - spec and plan targets remain hub-owned
      - implementation branches and PRs are inspected in the product repository
      - reviewer loop and CI loop command construction uses the selected product
        repository slug
      - post-merge cleanup deletes product branches in the product checkout and
        leaves hub branches alone
      - tracker status/type helpers still use the hub project context
      - file-conflict detection does not compare hub paths to product paths as
        the same namespace

### Documentation

- [ ] Update `docs/workflow/development-workflow/repository-modes.md` with
      orchestration ownership rules.
- [ ] Update `docs/workflow/development-workflow/README.md` to mention product
      repository selection for workflow hub implementation work.
- [ ] Update relevant protocol text only if the implementation introduces a new
      required flag or output field for orchestrators to pass.
- [ ] Add the implementation changelog entry under `[Unreleased]` / `### Changed`:
      `- **Workflow hub orchestration repository awareness** (#878): routes implementation branch, pull request, reviewer, CI, and cleanup operations to the selected product repository while keeping tracker/spec/plan state in the hub.`

### Database / Frontend / Infrastructure

- [ ] None. This feature changes workflow scripts, tests, and documentation
      only. It must not require secrets or live product repositories in CI.

---

## Testing Strategy

**Test types**: Shell fixture tests, command-contract tests, single-repository
regression tests, workflow hub multi-product tests, shellcheck, and markdown
lint.

**Key scenarios to test**:

1. Missing mode and explicit `single_repo` preserve discovery, next-action,
   batch, reviewer, CI, and cleanup behavior (AC1).
2. `workflow_hub` implementation next-action planning resolves and reports one
   selected product repository (AC2).
3. Missing or ambiguous product repository selection fails before product
   implementation inspection or mutation (AC3, AC9).
4. Discovery and batch planning separate hub-owned tracker/spec/plan state from
   product-owned implementation branch/PR state (AC4).
5. Reviewer loop targets the selected product repository for implementation PRs
   and reports it (AC5).
6. CI loop targets the selected product repository for implementation PRs and
   reports it (AC6).
7. Post-merge cleanup acts in the owning repository and keeps tracker updates
   hub-owned (AC7).
8. Project status/type helpers remain hub-owned unless explicitly configured
   otherwise (AC8).
9. Multi-product and single-repository fixture paths both pass (AC10).

**Smoke test runbook**:
`docs/testing/workflow/878-workflow-orchestration-product-repo-aware.smoke-test.md`

**Regression suite**:

- `bash scripts/development-workflow/tests/test-workflow-config-resolver.sh`
- `bash scripts/development-workflow/tests/test-workflow-orchestration-product-repo-aware.sh`
- `bash scripts/development-workflow/tests/test-workflow-lib-github-projects.sh`
- `bash scripts/development-workflow/tests/test-pr-review-loop.sh`
- `shellcheck --severity=warning scripts/development-workflow/*.sh scripts/development-workflow/tests/*.sh`
- `python3 -m py_compile scripts/development-workflow/workflow-config-resolver.py`
- `npx markdownlint-cli2 "docs/specs/developments/20260610164605_878-workflow-orchestration-product-repo-aware/*.md" "docs/testing/workflow/878-workflow-orchestration-product-repo-aware.smoke-test.md" "CHANGELOG.md"`
- `python3 scripts/lint/markdown-heuristic-lint.py docs/testing/workflow/878-workflow-orchestration-product-repo-aware.smoke-test.md CHANGELOG.md`
- `bash scripts/lint/check-changelog-duplicate-headers.sh CHANGELOG.md`

### Parser-risk Addendum

- **Edge-case enumeration**:
  - no mode declaration
  - explicit `single_repo`
  - explicit `workflow_hub` with one product repo
  - explicit `workflow_hub` with two product repos and no selection
  - unknown product repository selection
  - selected product repo with `github_repo`
  - selected product repo with GitHub-form `git_url`
  - selected product repo with non-GitHub `git_url`
  - selected product repo missing local path for branch cleanup
  - spec branch in workflow hub mode
  - implementation-plan branch in workflow hub mode
  - feature branch in workflow hub mode
  - open implementation PR in the product repository
  - open spec or plan PR in the hub repository
  - same relative file path in hub and product repositories
  - tracker status update while a product repo is selected
  - `--repo` missing value and unknown option handling in each updated script
- **Unit test mapping**: Add one named assertion for each edge case in
  `scripts/development-workflow/tests/test-workflow-orchestration-product-repo-aware.sh`.
- **Suppression semantics**: No new suppression directive format is introduced.
  Any ShellCheck suppression must follow the existing line-level directive with
  inline rationale required by `docs/best-practices/1-general.md`.

---

## Seed Data

No persistent seed data is required. Tests should create temporary hub and
product repository fixtures with local git repositories and stubbed `gh`
responses where needed.

---

## Documentation Updates

- [ ] `docs/workflow/development-workflow/repository-modes.md` - document
      orchestration ownership and product selection.
- [ ] `docs/workflow/development-workflow/README.md` - describe selected product
      repository routing for workflow hub implementation work.
- [ ] Protocol documents touched by implementation, if new required flags or
      output fields must be part of the workflow contract.
- [ ] `CHANGELOG.md` - add the implementation entry listed in the Documentation
      layer above.

---

## Risks & Mitigations

| Risk | Likelihood | Impact | Mitigation |
| --- | --- | --- | --- |
| Existing single-repo adopters are forced to pass product repo flags | Medium | High | Make missing mode resolve as `single_repo` and add regression tests for each updated script. |
| Reviewer or CI loop reads the hub PR instead of the product PR | Medium | High | Require an explicit repo slug for product implementation PRs and include `REPO=` in output. |
| Tracker helper targets the product repository project by accident | Low | High | Keep tracker helpers hub-owned and add a selected-product regression test. |
| File conflict detection compares paths across repositories | Medium | Medium | Include repository namespace in batch-plan file-set comparisons. |
| Cleanup deletes a branch in the wrong checkout | Medium | High | Resolve ownership from branch type and product selection before branch deletion; fail closed on ambiguity. |

---

## Code Samples

No production code samples are required. Implementation should prefer
well-named shell helpers and stable `KEY=value` output over inline shell
fragments in documentation.

---

## Implementation Order

1. Add repository-context helper support needed by orchestration: product repo
   list, GitHub slug derivation, and implementation repository context output.
2. Update `discover-workflow-state.sh` to accept product repository selection,
   preserve single-repo output, and separate hub-owned from product-owned state.
3. Update `workflow-next-action.sh` to route implementation branch and PR
   inspection to the selected product repository while keeping spec/plan checks
   hub-owned.
4. Update `workflow-batch-plan.sh` to pass repository selection through and
   namespace file-conflict checks by repository.
5. Update `pr-review-loop.sh` so implementation PR review calls target the
   selected product repository and summary output names the repository.
6. Update `pr-ci-loop.sh` so implementation PR check polling targets the
   selected product repository and emits the repository slug.
7. Update `post-merge-cleanup.sh` so branch/worktree cleanup runs in the owning
   repository while tracker updates remain hub-owned.
8. Add shell fixture tests for single-repository regression, multi-product
   selection, missing/ambiguous selection, product PR review/CI routing, and
   cleanup ownership.
9. Update project docs per **Documentation Updates**.
10. Add the CHANGELOG entry:
    `- **Workflow hub orchestration repository awareness** (#878): routes implementation branch, pull request, reviewer, CI, and cleanup operations to the selected product repository while keeping tracker/spec/plan state in the hub.`
11. Run the regression suite from **Testing Strategy** and fix any failures.
