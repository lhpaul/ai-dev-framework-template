# Workflow Hub Product Repository Sync and Status Scripts - Implementation Plan

**Spec**: [1_877-workflow-hub-product-repo-sync-status-scripts_specs.md](1_877-workflow-hub-product-repo-sync-status-scripts_specs.md)
**Smoke test runbook**: [877-workflow-hub-product-repo-sync-status-scripts.smoke-test.md](../../../testing/workflow/877-workflow-hub-product-repo-sync-status-scripts.smoke-test.md)

---

## Summary

**Approach**: Add workflow-hub-only command wrappers for status, sync, and pull
request visibility that consume the repository-context helpers from #875. Keep
the commands conservative: status and PR listing are read-only, sync refuses
dirty checkouts, and any local-path bootstrap path requires an explicit
confirmation flag before writing `.ai-dev-workflow.local.yaml`.

**Estimated complexity**: M

**Rationale**: The work is script-heavy and safety-sensitive, but it can stay
bounded by reusing the existing repository-context resolver instead of adding
new config parsing. The main risk is command behavior around missing paths,
dirty checkouts, and partial multi-repository results.

**Dependencies**: #875 must be merged into `develop-workflow-hub-mode` before
implementation starts because this feature depends on
`workflow-config-resolver.py` and the `workflow-lib.sh` repository-context
wrappers.

---

## Verification Log

| Check | Command / query | Result |
| --- | --- | --- |
| Repo revision | `git rev-parse --short HEAD` | `8b30a37` |
| Approved spec | `sed -n '1,340p' docs/specs/developments/20260610164114_877-workflow-hub-product-repo-sync-status-scripts/1_877-workflow-hub-product-repo-sync-status-scripts_specs.md` | Spec defines status, sync, optional PR listing, wrong-mode refusal, dirty-checkout refusal, missing-path guidance, explicit bootstrap confirmation, and shell validation coverage. |
| Dependency implementation | `find scripts/development-workflow -maxdepth 1 -type f \| sort` | #875 has introduced `workflow-config-resolver.py` and `validate-workflow-config.sh`. |
| Repository-context wrappers | `rg -n "workflow_repository_context\|workflow_repository_mode\|workflow_validate_repository_context" scripts/development-workflow/workflow-lib.sh` | `workflow-lib.sh` exposes shell-callable helpers for mode and repository context resolution. |
| Resolver behavior tests | `rg -n "checkout_root\|TARGET_LOCAL_PATH\|require-local" scripts/development-workflow/tests/test-workflow-config-resolver.sh` | Existing resolver tests cover local overrides, checkout-root defaults, and require-local missing-path failures. |
| Existing workflow tests | `find scripts/development-workflow/tests -maxdepth 1 -type f \| sort` | Shell harness convention is `scripts/development-workflow/tests/test-*.sh`. |
| Existing smoke runbooks | `find docs/testing/workflow -maxdepth 1 -type f \| sort` | Workflow smoke runbooks live in `docs/testing/workflow/`. |

---

## Layer-by-Layer Changes

### Backend / Scripts

- [ ] Add `scripts/development-workflow/hub-status.sh`.
      - Support `--repo <name>`, `--all`, `--repo-root <path>`, and `--help`.
      - Require `workflow_hub` mode before inspecting product checkouts.
      - Use `workflow_repository_context` from `workflow-lib.sh`.
      - For each selected product repository, report local path, branch, clean
        or dirty working tree, remote visibility, and one of the spec status
        codes: `clean`, `dirty`, `missing_path`, `missing_checkout`, or
        `failed`.
      - Keep the command read-only.
- [ ] Add `scripts/development-workflow/hub-sync-product-repos.sh`.
      - Support `--repo <name>`, `--all`, `--repo-root <path>`, optional
        `--bootstrap-local-path`, optional `--yes`, and `--help`.
      - Require `workflow_hub` mode before inspecting or syncing product
        checkouts.
      - Refuse to sync a checkout when `git -C <path> status --porcelain`
        returns any content.
      - For clean checkouts, fetch the remote and fast-forward the configured
        default branch only when the local branch is not ahead of origin.
      - Fail closed on true divergence or local-ahead-only state; report the
        branch/path and do not push, rebase, reset, stash, or force update.
      - Return a final summary that separates `synced`, `skipped`, `blocked`,
        and `failed` repositories.
- [ ] Add `scripts/development-workflow/hub-list-prs.sh`.
      - Support `--repo <name>`, `--all`, `--repo-root <path>`, and `--help`.
      - Resolve each selected repository's GitHub identity from
        repository-context output.
      - Prefer `TARGET_GITHUB_REPO` when present. When only `TARGET_GIT_URL`
        is present, derive a GitHub `owner/repo` slug only for recognized
        GitHub URL forms such as `git@github.com:owner/repo.git`,
        `https://github.com/owner/repo.git`, or
        `ssh://git@github.com/owner/repo.git`.
      - Fail clearly when no GitHub repository slug can be resolved; do not
        silently fall back to the workflow hub repository.
      - Use `gh pr list --repo <owner/repo>` and print PR number, title, head,
        base, draft state, and readiness labels.
      - Keep the command read-only and report remote-inspection errors per
        repository.
- [ ] Extend the #875 resolver or `workflow-lib.sh` with a shell-callable way
      to list configured product repository names for `--all`.
      - Prefer a resolver subcommand such as `list-product-repos` that emits one
        repository name per line after validating `workflow_hub` mode.
      - Use the same list helper in all three commands so `--all` cannot drift
        across status, sync, and PR listing behavior.
      - Reject `--repo` and `--all` together before calling the resolver.
- [ ] Add local-path bootstrap support only behind explicit confirmation.
      - Without `--bootstrap-local-path`, print the exact
        `.ai-dev-workflow.local.yaml` entry the operator can add.
      - With `--bootstrap-local-path` but without `--yes`, prompt on stdin and
        require an affirmative response.
      - With both flags, append or update only the selected product repository
        local-path entry in `.ai-dev-workflow.local.yaml`.
      - Never write token values, private key values, or secret references from
        this command.

### Tests

- [ ] Add
      `scripts/development-workflow/tests/test-workflow-hub-product-repo-commands.sh`.
- [ ] Build tests with temporary fixture repos created under `mktemp -d` so no
      developer checkout is mutated.
- [ ] Cover:
      - help output for all three commands
      - wrong-mode failure before checkout inspection
      - status for one clean product repo
      - status for `--all` with mixed clean, dirty, missing path, and missing
        checkout outcomes
      - sync refusal for a dirty checkout
      - sync partial success and failure summary for `--all`
      - missing local path guidance naming `.ai-dev-workflow.local.yaml`
      - bootstrap declined, confirmed interactively, and confirmed with `--yes`
      - PR listing dry fixture with `gh` unavailable or remote inspection
        failure producing a per-repository `failed` result
      - PR listing for a repository declared only with a GitHub `git_url`
      - PR listing for a repository whose `git_url` is not a GitHub URL,
        proving the command fails clearly instead of targeting the hub
- [ ] Add any new test harness to the same execution path used by existing
      workflow script tests.

### Documentation

- [ ] Update `scripts/development-workflow/README.md` with command purpose,
      mode requirement, target-selection options, and safe-failure behavior.
- [ ] Update `docs/workflow/development-workflow/repository-modes.md` to point
      workflow hub operators to the new status, sync, and PR visibility
      commands.
- [ ] Add the implementation changelog entry under `[Unreleased]` / `### Added`:
      `- **Workflow hub product repository commands** (#877): adds workflow-hub status, sync, and pull-request visibility commands for product repository checkouts.`

### Infrastructure / Configuration

- [ ] No new versioned secrets or machine-local paths.
- [ ] No CI secret requirement. Tests must run with local fixture repositories.
- [ ] No database, frontend, or deployment changes.

---

## Testing Strategy

**Test types**: Shell fixture tests, command help tests, config-mode failure
tests, smoke runbook validation, shellcheck, and markdown lint.

**Key scenarios to test**:

1. Help output names purpose, required mode, target selection, and safe failure
   behavior for each command (AC1).
2. All commands fail clearly outside `workflow_hub` mode before product checkout
   inspection or mutation (AC2).
3. `hub-status.sh --repo <name>` reports local path, branch, cleanliness, and
   remote visibility for one repository (AC3).
4. `hub-status.sh --all` reports per-repository outcomes plus a final summary
   (AC4).
5. `hub-sync-product-repos.sh --repo <name>` refuses a dirty checkout (AC5).
6. `hub-sync-product-repos.sh --all` reports partial success and blocked
   repositories without hiding either result (AC6).
7. Missing local paths report a default or the exact local config entry to add
   (AC7).
8. Bootstrap writes only after explicit confirmation (AC8).
9. `hub-list-prs.sh` is read-only and supports one repository or all
   repositories (AC9).
10. Shell validation covers the command matrix above (AC10).

**Smoke test runbook**:
`docs/testing/workflow/877-workflow-hub-product-repo-sync-status-scripts.smoke-test.md`

**Regression suite**:

- `bash scripts/development-workflow/tests/test-workflow-config-resolver.sh`
- `bash scripts/development-workflow/tests/test-workflow-hub-product-repo-commands.sh`
- `bash scripts/development-workflow/tests/test-workflow-lib-github-projects.sh`
- `shellcheck --severity=warning scripts/development-workflow/*.sh scripts/development-workflow/tests/*.sh`
- `npx markdownlint-cli2 "docs/specs/developments/20260610164114_877-workflow-hub-product-repo-sync-status-scripts/*.md" "docs/testing/workflow/877-workflow-hub-product-repo-sync-status-scripts.smoke-test.md" "CHANGELOG.md"`
- `python3 scripts/lint/markdown-heuristic-lint.py docs/testing/workflow/877-workflow-hub-product-repo-sync-status-scripts.smoke-test.md CHANGELOG.md`
- `bash scripts/lint/check-changelog-duplicate-headers.sh CHANGELOG.md`

### Parser-risk Addendum

- **Edge-case enumeration**:
  - `--repo` with a missing value.
  - `--repo` and `--all` passed together.
  - unknown option.
  - help requested with invalid or absent workflow configuration.
  - missing mode and explicit `single_repo`.
  - explicit `product_repo` mode.
  - `workflow_hub` with one product repo.
  - `workflow_hub` with multiple product repos and no selection.
  - missing local path with and without `--bootstrap-local-path`.
  - bootstrap confirmation declined, accepted through stdin, and accepted with
    `--yes`.
  - local path exists but is not a git checkout.
  - checkout on default branch and clean.
  - checkout on non-default branch and clean.
  - checkout dirty through unstaged, staged, and untracked changes.
  - remote inspection succeeds, fails due to missing remote, and fails due to
    `gh` or network error.
  - PR listing with `TARGET_GITHUB_REPO`.
  - PR listing with a GitHub-form `TARGET_GIT_URL`.
  - PR listing with a non-GitHub `TARGET_GIT_URL`.
  - sync local behind only, local ahead only, true divergence, and remote branch
    missing.
  - multi-repository status with mixed outcome categories.
- **Unit test mapping**: Map each edge case to a named assertion in
  `scripts/development-workflow/tests/test-workflow-hub-product-repo-commands.sh`.
- **Suppression semantics**: ShellCheck suppressions may be used only with a
  line-level `# shellcheck disable=...` directive and inline rationale, following
  `docs/best-practices/1-general.md`.

---

## Seed Data

No persistent seed data is required. Tests should create temporary workflow hub
configs, local config files, and throwaway product repository fixtures under
`mktemp -d`.

---

## Documentation Updates

- [ ] `scripts/development-workflow/README.md` - add status, sync, and PR
      listing command usage.
- [ ] `docs/workflow/development-workflow/repository-modes.md` - add workflow
      hub operator guidance for inspecting and preparing product repositories.
- [ ] `CHANGELOG.md` - add the implementation entry listed in the Documentation
      layer above.

---

## Risks & Mitigations

| Risk | Likelihood | Impact | Mitigation |
| --- | --- | --- | --- |
| Sync mutates a dirty checkout | Medium | High | Check `git status --porcelain` before fetch or pull and block on any output. |
| A command acts outside workflow hub mode | Medium | High | Resolve mode first and fail before checkout inspection or mutation. |
| Partial `--all` results hide blocked repositories | Medium | Medium | Track per-repository outcomes and always print a categorized final summary. |
| Bootstrap corrupts local config | Low | Medium | Keep bootstrap opt-in, fixture-test append/update behavior, and write only local path fields. |
| PR listing accidentally targets the hub repo | Medium | Medium | Always pass `--repo <owner/repo>` from resolved product context to `gh pr list`. |

---

## Code Samples

No production code samples are required in this plan. Implementation should
prefer small shell functions with explicit argument validation and structured
status output.

---

## Implementation Order

1. Add the command argument parser and workflow-hub mode guard for
   `hub-status.sh`; verify `--help` works without valid config and wrong mode
   fails before checkout inspection.
2. Extend the repository-context layer with a shell-callable product repository
   list helper for `--all`, then implement product repository selection for one
   repository and all repositories using #875 helpers. Verify missing,
   ambiguous, and mutually exclusive selection states produce clear errors.
3. Implement read-only status inspection and categorized summary output.
4. Add `hub-sync-product-repos.sh` with the same selection contract and dirty
   checkout guard; verify dirty checkouts are blocked before any sync command.
5. Implement conservative clean-checkout sync: fetch, detect ahead/behind, fast
   forward only when safe, and fail closed on divergence or local-ahead state.
6. Add missing-path guidance and explicit local-path bootstrap behavior.
7. Add `hub-list-prs.sh` as a read-only visibility command that uses resolved
   product repository identity with `gh pr list --repo`, including GitHub
   `git_url` slug derivation and clear failure when no GitHub slug is
   available.
8. Add
   `scripts/development-workflow/tests/test-workflow-hub-product-repo-commands.sh`
   with fixture coverage for all acceptance criteria and parser-risk edge
   cases.
9. Update project docs per **Documentation Updates**.
10. Add the CHANGELOG entry:
    `- **Workflow hub product repository commands** (#877): adds workflow-hub status, sync, and pull-request visibility commands for product repository checkouts.`
11. Run the regression suite from **Testing Strategy** and fix any failures.
