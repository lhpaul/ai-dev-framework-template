# Workflow Hub Smoke Fixtures and Backwards-Compatibility Checks - Implementation Plan

**Spec**: [1_883-workflow-hub-smoke-fixtures_specs.md](1_883-workflow-hub-smoke-fixtures_specs.md)
**Smoke test runbook**: [883-workflow-hub-smoke-fixtures.smoke-test.md](../../../testing/workflow/883-workflow-hub-smoke-fixtures.smoke-test.md)

---

## Summary

**Approach**: Add a non-secret workflow-hub fixture seed and a shell smoke
harness that copies the seed into temporary hub/product repositories, runs the
workflow-hub helpers in fixture or dry-run mode, and verifies single-repository
regression behavior in the same default test path. Keep live GitHub App checks
as an explicit opt-in path that never runs in CI by default.

**Estimated complexity**: L

**Rationale**: This is a cross-feature validation layer, not one helper change.
It must exercise config parsing, product repository resolution, sync/status
behavior, branch and PR routing, mode-specific sync scope, auth dry-run behavior,
and single-repo regression without requiring private repositories or secrets.
The implementation depends on several workflow-hub features landing first, so
the plan names fixture boundaries and skip/require behavior explicitly.

**Dependencies**: #875, #876, #877, #878, and #880 must be merged into
`develop-workflow-hub-mode` before this implementation can run the full default
fixture suite. The implementation PR must not be marked ready for human review
while any default #883 acceptance-criterion check is skipped for a missing
dependency. Temporary `SKIP_DEPENDENCY=<issue>` output is acceptable only as a
local development diagnostic before the dependency branch lands.

---

## Verification Log

| Check | Command / query | Result |
| --- | --- | --- |
| Repo revision | `git rev-parse --short HEAD` | `8b30a37` |
| Approved spec | `sed -n '1,420p' docs/specs/developments/20260610170359_883-workflow-hub-smoke-fixtures/1_883-workflow-hub-smoke-fixtures_specs.md` | Spec requires non-secret hub fixture coverage, two product repos, config/resolution, sync/status, branch/PR routing, mode-specific sync scope, single-repo regression, CI default coverage, and optional live auth validation. |
| Existing workflow-hub fixture style | `sed -n '1,260p' scripts/development-workflow/tests/test-workflow-hub-skeletons.sh` | Current shell tests create temporary fixture repos with helper functions, pass/fail counters, and deterministic output. |
| Current committed skeletons | `find template -maxdepth 3 -type f \| sort` | `template/workflow-hub/` and `template/product-repo-injection/` provide inspectable hub/product skeleton inputs. |
| Existing workflow tests | `find scripts/development-workflow/tests -maxdepth 1 -type f \| sort` | Tests live under `scripts/development-workflow/tests/`; no shared committed fixture seed directory exists yet. |
| Repository modes | `sed -n '1,260p' docs/workflow/development-workflow/repository-modes.md` | Mode docs define `workflow_hub`, `product_repo`, local config path resolution, and `.tmp/template-config.json` compatibility boundaries. |
| Sync-manifest mode scopes | `sed -n '1,220p' sync-manifest.yaml` | `mode_scope` values exist as `shared`, `hub_only`, and `product_repo_injection`; current readers treat them as informational until mode-aware sync work consumes them. |
| CI test surface | `find .github/workflows -maxdepth 1 -type f \| sort` plus `rg -n "development-workflow/tests" .github/workflows` | CI already runs targeted workflow shell tests for PR review loop; #883 should add the new fixture harness to a relevant workflow path only after it is deterministic and non-secret. |

---

## Layer-by-Layer Changes

### Backend / Scripts

- [ ] Add a committed non-secret fixture seed under
      `scripts/development-workflow/tests/fixtures/workflow-hub-smoke/`.
      - Include a `README.md` explaining that files are placeholders and must
        not contain private repo names, customer names, team names, tokens,
        private key paths, or live secret-manager locations.
      - Include hub shared config with `mode: workflow_hub` and two product
        repos, for example `mobile-app` and `admin-portal`, using
        `example/mobile-app` and `example/admin-portal` identities.
      - Include local config seed data as a fixture template, not as the
        repository's real `.ai-dev-workflow.local.yaml`.
      - Include expected-output snippets only when they are stable enough to
        avoid brittle line-count assertions.
- [ ] Add `scripts/development-workflow/tests/test-workflow-hub-smoke-fixtures.sh`.
      - Follow the existing shell harness style in
        `test-workflow-hub-skeletons.sh`: `set -euo pipefail`, temp directory
        cleanup, pass/fail counters, `run_test`, `run_contains`, and
        `run_fails_contains`.
      - Copy fixture seed files into a temp workflow hub checkout.
      - Create two temporary product repository directories and initialize them
        as local git repositories only when the specific check needs git state.
      - Materialize `.ai-dev-workflow.local.yaml` inside the temp hub from the
        fixture local template and temp paths.
      - Print stable section headers that distinguish `hub_fixture`,
        `product_fixture`, `dry_run_routing`, `single_repo_regression`, and
        `live_optional` areas.
- [ ] Cover workflow config parsing and product repository resolution.
      - Run `workflow-config-resolver.py mode`, `resolve --repo mobile-app`,
        `resolve --repo admin-portal`, and `validate --require-local` against
        the temp hub.
      - Verify `WORKFLOW_MODE=workflow_hub`, distinct product names, distinct
        repository identities, default branch resolution, local path source
        ordering, and ambiguous selection failure.
      - Verify local checkout paths come from the temp local config or
        documented `checkout_root` default, never from
        `.tmp/template-config.json`.
- [ ] Cover sync/status behavior once #877 helpers are available.
      - Run the product repo status helper in non-mutating or fixture mode for
        each dummy product repository.
      - Verify output names the hub, both products, resolved local paths,
        branch status, and any sync status fields defined by #877.
      - Add failure cases for unknown product repo and missing local path when
        local checkout is required.
- [ ] Cover branch and pull-request routing once #878 and #880 helpers are
      available.
      - Use dry-run or stubbed command mode only.
      - Verify branch/PR routing commands include the selected product
        repository slug, base branch, head branch, and title.
      - Verify no command targets the workflow hub remote for product-owned
        implementation work.
      - Verify no token, private key, or secret-ref fixture value appears in
        captured stdout/stderr.
- [ ] Cover mode-specific sync-template behavior.
      - Add a mode-scope validation command or fixture check that proves
        `hub_only`, `product_repo_injection`, and `shared` entries are
        classified correctly from `sync-manifest.yaml`.
      - Keep the required #883 check at the validator/classification layer when
        runtime mode-aware filtering is still not implemented, because current
        `sync-manifest.yaml` states that `mode_scope` metadata is informational.
      - If a dependency has added dry-run mode-aware filtering by the time #883
        is implemented, call it for `workflow_hub` and `product_repo` and
        verify the selected paths in addition to the classification checks.
- [ ] Cover single-repository regression in the same harness.
      - Create a temp repository with no `mode` declaration and another with
        `mode: single_repo`.
      - Run config resolution and the smallest available discovery/next-action
        check that does not require tracker access.
      - Assert product repository selection is not required and hub local config
        is not required.
- [ ] Add optional live GitHub App validation behind an explicit flag.
      - Use a flag such as `--live-github-app` plus required environment
        variables for safe test repository names.
      - Default to `LIVE_VALIDATION=skipped` with a clear explanation.
      - Fail closed if the flag is provided but required safe-test credentials
        are missing.
      - Do not add the live flag to CI.

### Tests

- [ ] Add the new fixture harness to the default workflow test set when all
      default checks are deterministic and secret-free.
      - Prefer adding it to `.github/workflows/test-pr-review-loop.yml` only if
        that workflow remains the canonical development-workflow test job, or
        create a narrowly named workflow such as
        `.github/workflows/workflow-hub-smoke.yml`.
      - Trigger on paths touching workflow-hub scripts, config resolver,
        repository-mode docs, sync manifest, fixture seed files, and the new
        harness.
- [ ] Keep the harness independent of network and real GitHub auth by default.
- [ ] Include test cases for:
      - fixture seed files contain no private detail strings
      - fixture hub has exactly two product repos
      - product repos have distinct names and identities
      - config resolver parses both products
      - ambiguous product selection fails
      - local path override wins over `checkout_root`
      - `checkout_root` default works for the second product
      - `.tmp/template-config.json` does not provide checkout paths
      - sync/status dry-run names both products
      - branch/PR dry-run targets product repos, not the hub
      - mode-scope classification separates `hub_only`,
        `product_repo_injection`, and `shared`
      - missing mode defaults to `single_repo`
      - explicit `single_repo` does not require product selection
      - optional live validation is skipped by default
      - optional live validation fails clearly when requested without required
        safe-test credentials

### Documentation

- [ ] Update `docs/workflow/development-workflow/repository-modes.md`.
      - Add a short fixture section describing the committed workflow-hub smoke
        fixture, default non-secret behavior, and optional live validation.
- [ ] Update `docs/workflow/development-workflow/README.md`.
      - Add the one-command local smoke fixture invocation after workflow-hub
        mode documentation.
      - State that CI runs the non-secret path only.
- [ ] Update the fixture `README.md` with:
      - one local command
      - fixture topology
      - no-secret policy
      - optional live validation command and required safe-test variables
- [ ] Add the implementation changelog entry under `[Unreleased]` / `### Added`:
      `- **Workflow hub smoke fixtures** (#883): adds non-secret workflow hub and product repository fixture coverage with single-repository regression checks.`

### Database / Frontend / Infrastructure

- [ ] None for database or frontend.
- [ ] CI changes are limited to running the new non-secret shell harness on
      relevant workflow-hub paths. No CI secret or live product repository is
      required.

---

## Testing Strategy

**Test types**: Shell fixture tests, config resolver regression tests,
mode-scope classification tests, dry-run routing tests, no-secret scans,
single-repository regression tests, optional live validation checks,
shellcheck, and markdown lint.

**Key scenarios to test**:

1. The committed fixture seed exists, contains one hub and two dummy product
   repos, and contains no private names or secret-looking values (AC1, AC2,
   AC9).
2. Config parsing resolves both product repos with distinct repository
   identities and fails clearly for ambiguous or unknown selection (AC3).
3. Local checkout paths resolve from `.ai-dev-workflow.local.yaml` or
   `checkout_root`, and `.tmp/template-config.json` is not accepted as a checkout
   path source (AC7).
4. Sync/status dry-run coverage reports both dummy product repos and fails
   clearly for missing local paths or unknown repo selections (AC4).
5. Branch and PR dry-run routing targets the selected product repository and
   does not open real PRs or print secret material (AC5, AC9).
6. Mode-scope classification separates hub-only files from product-injection
   files and shared files (AC6).
7. Missing mode and explicit `single_repo` cases remain green without product
   repository selection (AC8).
8. Default CI path runs the non-secret harness with no private repositories,
   live GitHub App credentials, or production secrets (AC9).
9. Optional live GitHub App validation is skipped by default and only runs when
   explicitly requested with safe-test configuration (AC10).

**Smoke test runbook**:
`docs/testing/workflow/883-workflow-hub-smoke-fixtures.smoke-test.md`

**Regression suite**:

- `bash scripts/development-workflow/tests/test-workflow-hub-smoke-fixtures.sh`
- `bash scripts/development-workflow/tests/test-workflow-config-resolver.sh`
- `bash scripts/development-workflow/tests/test-workflow-hub-skeletons.sh`
- #877 sync/status helper tests once available
- #878 orchestration routing tests once available
- #880 PR auth helper tests once available
- `shellcheck --severity=warning scripts/development-workflow/*.sh scripts/development-workflow/tests/*.sh`
- `python3 -m py_compile scripts/development-workflow/workflow-config-resolver.py scripts/development-workflow/validate-workflow-hub-skeletons.py`
- `npx markdownlint-cli2 "docs/specs/developments/20260610170359_883-workflow-hub-smoke-fixtures/*.md" "docs/testing/workflow/883-workflow-hub-smoke-fixtures.smoke-test.md" "CHANGELOG.md"`
- `python3 scripts/lint/markdown-heuristic-lint.py docs/testing/workflow/883-workflow-hub-smoke-fixtures.smoke-test.md CHANGELOG.md`
- `bash scripts/lint/check-changelog-duplicate-headers.sh CHANGELOG.md`

### Parser-risk Addendum

- **Edge-case enumeration**:
  - fixture seed directory missing
  - fixture seed contains private detail string
  - fixture seed contains token-like value
  - fixture seed contains private key path
  - fixture hub has zero product repos
  - fixture hub has one product repo
  - fixture hub has three product repos
  - duplicate product repo names
  - duplicate product repo identities
  - selected product repo has `github_repo`
  - selected product repo has GitHub `git_url`
  - selected product repo has non-GitHub `git_url`
  - no product repo selection in a two-product hub
  - unknown product repo selection
  - local path override present
  - only `checkout_root` present
  - no local path and no checkout root when local path is required
  - `.tmp/template-config.json` includes a checkout-looking value
  - product repo git directory missing
  - product repo git directory present
      - sync/status helper dry-run for both products
  - branch dry-run for product implementation work
  - PR dry-run for product implementation work
  - PR dry-run attempts to target hub remote
  - mode-scope entry is `hub_only`
  - mode-scope entry is `product_repo_injection`
  - mode-scope entry is `shared`
  - unknown mode-scope value
  - missing mode defaults to `single_repo`
  - explicit `single_repo`
  - optional live flag absent
  - optional live flag present with missing required env
  - optional live flag present with fixture safe-test env
- **Unit test mapping**: Add one named assertion for each edge case in
  `scripts/development-workflow/tests/test-workflow-hub-smoke-fixtures.sh`.
  Dependency skips may exist during local development, but the final
  implementation PR cannot be ready while any default assertion is skipped.
- **Suppression semantics**: No new suppression directive format is introduced.
  Any ShellCheck suppression must follow the existing line-level directive with
  inline rationale required by `docs/best-practices/1-general.md`.

---

## Seed Data

Seed data is committed only as non-secret fixture input under
`scripts/development-workflow/tests/fixtures/workflow-hub-smoke/`. The harness
must copy that seed into a temporary directory before creating local-only config
and temporary product repositories. No generated `.git` directory,
`.ai-dev-workflow.local.yaml`, token, private key, private repository name, or
secret-manager account detail should be committed.

---

## Documentation Updates

- [ ] `scripts/development-workflow/tests/fixtures/workflow-hub-smoke/README.md`
      - fixture topology, no-secret policy, local command, and optional live
      validation instructions.
- [ ] `docs/workflow/development-workflow/repository-modes.md` - fixture
      availability and scope.
- [ ] `docs/workflow/development-workflow/README.md` - one-command non-secret
      workflow-hub smoke invocation.
- [ ] `.github/workflows/test-pr-review-loop.yml` or new workflow-hub smoke CI
      workflow - run the non-secret harness on relevant paths.
- [ ] `CHANGELOG.md` - add the implementation entry listed in the Documentation
      layer above.
