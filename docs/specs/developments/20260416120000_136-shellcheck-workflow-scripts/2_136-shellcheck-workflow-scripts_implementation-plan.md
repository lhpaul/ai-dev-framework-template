# ShellCheck Static Analysis for Workflow Scripts — Implementation Plan

**Spec**: [`docs/specs/developments/20260416120000_136-shellcheck-workflow-scripts/1_136-shellcheck-workflow-scripts_specs.md`](./1_136-shellcheck-workflow-scripts_specs.md)
**Smoke test runbook**: [`docs/testing/workflow/136-shellcheck-workflow-scripts.smoke-test.md`](../../../../testing/workflow/136-shellcheck-workflow-scripts.smoke-test.md)

---

## Summary

**Approach**: Add a new GitHub Actions workflow (`.github/workflows/shellcheck.yml`) that runs ShellCheck against all `*.sh` files under `scripts/development-workflow/` on every pull request. The workflow uses a path filter so it only gates PRs that touch shell scripts. Any existing scripts with `warning`- or `error`-level findings at the time of implementation are addressed or suppressed inline in the same PR. A `.shellcheckrc` file is added to the repo root to suppress any project-wide structurally unfixable codes (e.g., SC1091 for unresolvable `source` paths), with each suppressed code documented by a comment explaining the reason.

**Estimated complexity**: S

**Rationale**: The change is a single new CI workflow file, optional `.shellcheckrc`, and targeted inline suppression directives (or fixes) in the existing scripts. No backend, frontend, database, or shared-library changes are needed. ShellCheck is available as a pre-installed tool on `ubuntu-latest` GitHub Actions runners.

**Dependencies**: None

---

## Layer-by-Layer Changes

### Infrastructure / Configuration

- [ ] Create `.github/workflows/shellcheck.yml` — new workflow that:
  - Triggers on `pull_request` events for branches targeting `develop` and `main`
  - Uses a `paths` filter: `['scripts/development-workflow/**/*.sh']` so the job only runs when shell scripts under that directory are touched
  - Runs on `ubuntu-latest`
  - Uses `actions/checkout@v5` to check out the PR branch
  - Runs `shellcheck --severity=warning scripts/development-workflow/**/*.sh` (or equivalent glob expansion) to find all `.sh` files under the target path
  - Exits with the ShellCheck exit code (non-zero on any `warning`/`error` findings)
  - Handles the edge case where no `.sh` files are found: exits green with an informational message
  - Completes within 2 minutes under normal conditions (no external network dependencies at analysis time)

- [ ] Optionally create `.shellcheckrc` in the repository root — only if the baseline scripts have project-wide structurally unfixable ShellCheck codes (e.g., SC1091 for `source` directives with dynamic paths). Each suppressed code must include an inline comment explaining the reason. If no project-wide suppressions are needed, this file is omitted.

### Workflow Scripts (`scripts/development-workflow/`)

- [ ] Run ShellCheck locally against all `*.sh` files under `scripts/development-workflow/` to establish the baseline findings list.
- [ ] For each `warning`- or `error`-level finding:
  - Fix the underlying issue where the correct fix is clear and low-risk (e.g., quoting an unquoted variable, correcting `set -e` interaction with pipeline commands).
  - Apply a targeted inline `# shellcheck disable=SCxxxx` directive on the specific line when the finding is a known false positive or an intentionally accepted pattern that cannot be fixed without altering behavior.
  - Prefer inline fixes over suppressions. Prefer line-scoped suppressions over file-wide suppressions.
- [ ] Verify that ShellCheck exits green (exit code 0) after all fixes and suppressions are applied.

---

## Testing Strategy

**Test types**: Manual / Smoke

**Key scenarios to test**:
1. PR touches a `.sh` file under `scripts/development-workflow/` with a `warning`-level ShellCheck finding → CI check fails (red) with specific file, line, code, and message shown — maps to Acceptance Criteria 1 and 2
2. PR touches a `.sh` file under `scripts/development-workflow/` with no findings → CI check passes (green) — maps to Acceptance Criterion 3
3. PR touches only non-shell files → ShellCheck job does not run (path filter skips it) or passes with no files found — maps to Acceptance Criterion 4
4. PR introduces an inline `# shellcheck disable=SCxxxx` directive for a known false positive → CI check passes (green) — maps to Acceptance Criterion 5
5. The implementation PR itself is merged and the check is green from day one — maps to Acceptance Criterion 6
6. `.shellcheckrc` file (if created) is committed and each entry has a comment — maps to Acceptance Criterion 7

**Smoke test runbook**: [`docs/testing/workflow/136-shellcheck-workflow-scripts.smoke-test.md`](../../../../testing/workflow/136-shellcheck-workflow-scripts.smoke-test.md)

**Regression suite**: Not applicable — no automated regression suite configured in this repository.

---

## Seed Data

Not applicable — this is a CI configuration and script-quality change; no application seed data is required.

---

## Documentation Updates

None. This feature adds a CI workflow and optional suppression configuration. It does not change the developer workflow beyond the new CI check, does not alter any established architectural pattern, and does not affect `docs/project/`, `docs/best-practices/`, or `AGENTS.md`. The new CI check's behavior is self-describing via its job name and ShellCheck output. If future scripts introduce new suppression patterns, the `.shellcheckrc` comments serve as the in-repository documentation.

---

## Risks & Mitigations

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| Existing scripts have many `warning`/`error` findings that require large-scale fixes | Medium | Medium | Run ShellCheck locally before implementation to scope the work; suppress only what cannot be immediately fixed, with inline comments explaining why |
| `shellcheck` binary is not pre-installed on the GitHub Actions runner image | Low | Low | Use `ubuntu-latest` where ShellCheck is pre-installed; add an explicit `apt-get install shellcheck` step as a fallback |
| Path filter glob does not match all `.sh` files in subdirectories | Low | Low | Test the glob pattern locally; use `find scripts/development-workflow -name "*.sh"` as an alternative if GitHub Actions glob expansion is insufficient |
| Adding `.shellcheckrc` with project-wide suppressions masks real issues added later | Low | Medium | Keep `.shellcheckrc` suppressions to the minimum needed; prefer inline suppressions scoped to specific lines |
| The workflow runs on PRs that don't touch workflow scripts but do touch other files in the repo, causing unexpected CI noise | Low | Low | The `paths` filter in the workflow trigger ensures the job only runs when `scripts/development-workflow/**/*.sh` files are changed |

---

## Code Samples

> All samples below are illustrative — adapt during implementation.

```yaml
# Illustrative — adapt during implementation
name: ShellCheck

on:
  pull_request:
    branches:
      - develop
      - main
    paths:
      - 'scripts/development-workflow/**/*.sh'

jobs:
  shellcheck:
    name: ShellCheck static analysis
    runs-on: ubuntu-latest
    steps:
      - name: Checkout
        uses: actions/checkout@v5

      - name: Run ShellCheck
        run: |
          mapfile -t shell_files < <(find scripts/development-workflow -name "*.sh")
          if [ ${#shell_files[@]} -eq 0 ]; then
            echo "No shell files found under scripts/development-workflow — skipping."
            exit 0
          fi
          shellcheck --severity=warning "${shell_files[@]}"
```

```ini
# .shellcheckrc — Illustrative — only add if structurally unfixable project-wide codes exist
# SC1091: ShellCheck cannot follow 'source' paths that are constructed dynamically at runtime.
# These paths are correct at runtime; suppressing to avoid false positives.
disable=SC1091
```

---

## Implementation Order

1. Run ShellCheck locally against all `*.sh` files under `scripts/development-workflow/` to produce the baseline findings list
2. Fix `warning`/`error`-level findings that have a clear, low-risk fix (e.g., quoting variables, removing unsafe patterns)
3. Apply targeted inline `# shellcheck disable=SCxxxx` directives for findings that are known false positives or intentionally accepted patterns; add a brief comment on each suppression explaining the reason
4. Create `.shellcheckrc` only if there are project-wide structurally unfixable codes that apply to multiple files; otherwise omit
5. Verify ShellCheck exits green (exit code 0) against the updated scripts
6. Create `.github/workflows/shellcheck.yml` with the path-filtered workflow as described above
7. Update `CHANGELOG.md` with an entry under `[Unreleased]` for this feature
8. Verify the smoke test runbook scenarios manually or via the CI run on the implementation PR
9. Update project docs per **Documentation Updates** section above (None required)
