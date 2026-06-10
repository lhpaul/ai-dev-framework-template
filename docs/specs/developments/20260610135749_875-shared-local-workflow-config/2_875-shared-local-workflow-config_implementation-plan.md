# Shared and Local Workflow Configuration - Implementation Plan

**Spec**: [1_875-shared-local-workflow-config_specs.md](1_875-shared-local-workflow-config_specs.md)
**Smoke test runbook**: [875-shared-local-workflow-config.smoke-test.md](../../../testing/workflow/875-shared-local-workflow-config.smoke-test.md)

---

## Summary

**Approach**: Add a single repository-context resolver for
`.ai-dev-workflow.yaml`, `.ai-dev-workflow.local.yaml`, and the legacy
`.tmp/template-config.json` override path. Expose that resolver through
shell-callable helpers in `workflow-lib.sh`, add a validation command, document
the shared/local schema, and cover the mode, product repository, local path, and
compatibility cases with fixture-driven tests.

**Estimated complexity**: M

**Rationale**: The change touches shared workflow configuration, shell helper
APIs, a new validation path, gitignore/example files, and test harnesses. The
main implementation risk is parsing nested YAML consistently without adding an
implicit runtime dependency.

**Dependencies**: #874 must be merged into `develop-workflow-hub-mode` before
the #875 implementation starts, because this item should extend the repository
mode documentation introduced by #874.

---

## Verification Log

| Check | Command / query | Result |
| --- | --- | --- |
| Repo revision | `git rev-parse --short HEAD` | `3144f30` |
| Issue brief and comments | `gh issue view 875 --json number,title,state,body,comments,labels` | Issue #875 is part of #873, has no scope-changing comments, and carries `integration-branch:workflow-hub-mode`. |
| Existing shared config | `sed -n '1,260p' .ai-dev-workflow.yaml` | Config currently has `schema_version`, `review`, `issue_tracker`, `vcs`, `browser_automation`, and `template`; no mode or repository-context fields. |
| Existing config helpers | `rg -n "template-config\|ai-dev-workflow\|workflow_hub\|product_repo\|github_repo\|git_url\|yq\|python" scripts docs .github .gitignore` | Existing helpers parse simple `.ai-dev-workflow.yaml` sections with awk and use `.tmp/template-config.json` for local review overrides; no repository-context resolver exists. |
| Python YAML dependency | `python3 - <<'PY' ... import yaml ... PY` | `pyyaml=no`; implementation must not assume PyYAML is installed. |
| Node YAML dependency | `rg -n "js-yaml\|yaml" package-lock.json package.json` | `js-yaml` is transitive through markdown tooling only; workflow scripts must not rely on uninstalled `node_modules`. |
| Local ignore state | `sed -n '1,160p' .gitignore` | `.tmp/` is ignored; `.ai-dev-workflow.local.yaml` is not ignored yet. |
| Existing workflow tests | `ls scripts/development-workflow/tests` | Test harnesses exist for `workflow-lib.sh`, PR review loop, Haystack, and skill install behavior. |

---

## Layer-by-Layer Changes

### Workflow Configuration

- [ ] Keep `.ai-dev-workflow.yaml` repo-safe: document but do not require an
      explicit mode for existing adopters.
- [ ] Add documentation for these shared fields:
      `mode`, `workflow_hub.product_repos[]`, and
      `product_repo.workflow_hub`.
- [ ] Define valid mode values as `single_repo`, `workflow_hub`, and
      `product_repo`.
- [ ] Enforce that a missing `mode` resolves as `single_repo`.
- [ ] Define shared product repository identity fields:
      `name`, `github_repo` or `git_url`, `default_branch`, optional
      `role`, optional `scope`, optional `tracker` hints, and optional
      non-secret app identifiers.
- [ ] Reject shared config that requires local checkout paths, private key
      paths, secret values, or machine-specific tool settings.

### Local Configuration

- [ ] Add `.ai-dev-workflow.local.yaml` to `.gitignore`.
- [ ] Add `.ai-dev-workflow.local.example.yaml` with placeholder-only examples
      for:
      - checkout root defaults
      - per-product local checkout paths
      - private key paths or secret references
      - local review/tool overrides
- [ ] Document that local config is optional in `single_repo` mode and required
      only when a workflow hub needs a local product checkout path that cannot
      be derived safely.
- [ ] Preserve `.tmp/template-config.json` as a compatibility fallback for
      existing review override behavior.
- [ ] Define override precedence explicitly:
      1. `.tmp/template-config.json` for legacy keys it already supports.
      2. `.ai-dev-workflow.local.yaml` for new local config keys.
      3. `.ai-dev-workflow.yaml` shared config.
      4. Built-in defaults such as missing mode -> `single_repo`.

### Backend / Scripts

- [ ] Add a dedicated repository-context resolver under
      `scripts/development-workflow/` rather than duplicating nested YAML
      parsing in multiple shell scripts.
- [ ] Keep the resolver dependency-light: use `python3` stdlib only, or another
      repository-declared dependency added and validated by CI. Do not rely on
      undeclared PyYAML or transitive `node_modules`.
- [ ] Make the resolver return shell-safe `KEY=value` output suitable for
      `workflow-lib.sh` callers.
- [ ] Add shell helper wrappers in `workflow-lib.sh` for:
      - reading the effective mode
      - resolving a product repository by stable name
      - resolving the current repository context in `single_repo` and
        `product_repo` modes
      - returning local path, GitHub repo slug, git URL, default branch, and
        tracker hints
      - validating required repository context before routing, branch, PR, or
        checkout actions
- [ ] Add a validation command, for example
      `scripts/development-workflow/validate-workflow-config.sh`, that prints
      resolved mode and target repository context on success and fails clearly
      on missing, duplicated, or ambiguous repository configuration.
- [ ] Ensure all new failure messages include the missing field or ambiguous
      selector and name the file the user should edit.

### Tests

- [ ] Add a focused repository-context test harness, for example
      `scripts/development-workflow/tests/test-workflow-config-resolver.sh`.
- [ ] Use temporary fixture directories and files so tests do not depend on the
      developer's real local config.
- [ ] Cover:
      - missing mode -> `single_repo`
      - explicit `single_repo`
      - valid `workflow_hub` with multiple product repositories
      - duplicate product repository names
      - missing `github_repo` and `git_url`
      - ambiguous product repository selection
      - valid `product_repo` hub reference
      - explicit local path override
      - derived local path from checkout root
      - missing local path clear error
      - `.tmp/template-config.json` compatibility behavior
      - local review/tool override precedence
- [ ] Update existing workflow test entry points when needed so CI runs the new
      harness.
- [ ] Add static validation for any new Python script, such as
      `python3 -m py_compile`.

### Documentation

- [ ] Extend the #874 repository modes note with shared/local configuration
      guidance once #874 is merged into the integration branch.
- [ ] Update `docs/workflow/development-workflow/README.md` to link the
      configuration guidance from the workflow configuration section.
- [ ] Update `.ai-dev-workflow.yaml` comments to point to the configuration
      guidance without enabling hub mode by default.
- [ ] Document `.tmp/template-config.json` compatibility and the preferred
      `.ai-dev-workflow.local.yaml` replacement path.
- [ ] Add the implementation changelog entry under `[Unreleased]` / `### Added`:
      `- **Shared and local workflow configuration** (#875): separates versioned repository identity from local checkout and secret references, with repository-context helpers for workflow hub routing.`

### Database / Data Layer

- [ ] None. This feature has no database, migration, seed, or data model
      changes.

### Frontend / UI

- [ ] None. This feature has no browser UI.

### Infrastructure / CI

- [ ] Update CI workflow paths only if a new test harness or resolver file would
      otherwise be skipped.
- [ ] Keep branch protection and reviewer-loop behavior unchanged.

---

## Testing Strategy

**Test types**: Unit-style shell fixture tests, config validation smoke tests,
markdown lint, shellcheck, and existing workflow harness regression tests.

**Key scenarios to test**:

1. Missing mode resolves as `single_repo` (AC1).
2. Shared docs describe `mode`, `workflow_hub.product_repos[]`, and
   `product_repo.workflow_hub` (AC2).
3. Hub config supports multiple named product repositories with `github_repo`
   or `git_url` identity (AC3, AC4).
4. Local-only config owns checkout paths, checkout roots, secret references,
   and tool overrides (AC5, AC6).
5. Helpers emit shell-callable context output for mode, local path, remote
   identity, default branch, and tracker hints (AC7).
6. Local path resolution uses explicit override, documented default, or clear
   error (AC8).
7. Validation fails clearly for missing, duplicate, or ambiguous product repo
   config (AC9).
8. `.tmp/template-config.json` behavior remains compatible or has documented
   migration coverage (AC10).
9. Tests cover `single_repo`, `workflow_hub`, `product_repo`, overrides, and
   missing path cases (AC11).

**Smoke test runbook**:
`docs/testing/workflow/875-shared-local-workflow-config.smoke-test.md`

**Regression suite**:

- `bash scripts/development-workflow/tests/test-workflow-config-resolver.sh`
- `bash scripts/development-workflow/tests/test-pr-review-loop.sh`
- `bash scripts/development-workflow/tests/test-workflow-lib-github-projects.sh`
- `shellcheck --severity=warning scripts/development-workflow/*.sh scripts/development-workflow/tests/*.sh`
- `python3 -m py_compile <new resolver script>` if the resolver is Python
- `npx markdownlint-cli2 "docs/specs/developments/20260610135749_875-shared-local-workflow-config/*.md" "docs/testing/workflow/875-shared-local-workflow-config.smoke-test.md" "CHANGELOG.md"`
- `python3 scripts/lint/markdown-heuristic-lint.py docs/testing/workflow/875-shared-local-workflow-config.smoke-test.md CHANGELOG.md`
- `bash scripts/lint/check-changelog-duplicate-headers.sh CHANGELOG.md`

### Parser-risk Addendum

- **Edge-case enumeration**:
  - missing `.ai-dev-workflow.yaml`
  - config present with no `mode`
  - quoted and unquoted scalar mode values
  - `workflow_hub.product_repos[]` with one entry
  - `workflow_hub.product_repos[]` with multiple entries
  - duplicate product repository `name`
  - entry with both `github_repo` and `git_url`
  - entry with neither `github_repo` nor `git_url`
  - local config path override matching by product repository `name`
  - checkout root default plus product repo name-derived path
  - local config file absent
  - `.tmp/template-config.json` present with existing review override shape
  - malformed shared YAML, malformed local YAML, and malformed legacy JSON
- **Unit test mapping**: Add one fixture test per edge case in
  `scripts/development-workflow/tests/test-workflow-config-resolver.sh`.
- **Suppression semantics**: Not applicable. The resolver does not implement
  lint suppressions.
- **Parser constraints**: If the implementation uses a constrained parser
  instead of a full YAML library, document supported YAML constructs in the
  configuration guide and fail closed on unsupported structures.

### Concurrent-Event-Source Addendum

Not applicable. This feature adds synchronous config resolution helpers and a
validation command. It does not add event listeners, timers, async queues, or
shared mutable runtime state.

---

## Seed Data

None. Tests should create temporary fixture config files.

---

## Documentation Updates

- [ ] `.ai-dev-workflow.yaml` - comment the new shared fields and link to the
      workflow configuration guide without enabling hub mode by default.
- [ ] `.ai-dev-workflow.local.example.yaml` - add safe local-only examples.
- [ ] `.gitignore` - ignore `.ai-dev-workflow.local.yaml`.
- [ ] `docs/workflow/development-workflow/repository-modes.md` - extend with
      shared/local configuration guidance after #874 merges.
- [ ] `docs/workflow/development-workflow/README.md` - link to the
      configuration guidance.
- [ ] `CHANGELOG.md` - add the implementation entry listed above.

---

## Risks & Mitigations

| Risk | Likelihood | Impact | Mitigation |
| --- | --- | --- | --- |
| Nested YAML parsing becomes fragile if implemented with ad hoc awk. | High | High | Use one dedicated resolver with fixture tests and shell wrappers; avoid duplicating nested parsing across scripts. |
| A new parser dependency is available locally but absent in CI or downstream repos. | Medium | High | Use stdlib-only code or add an explicit declared dependency and CI validation; do not rely on PyYAML or transitive packages. |
| Local config support changes existing `.tmp/template-config.json` behavior. | Medium | High | Preserve legacy precedence for supported keys and add compatibility tests. |
| Shared config accidentally stores local paths or secret references. | Medium | Medium | Document allowed shared fields and make validation flag local-only keys in shared product repo entries. |
| Hub validation rejects existing single-repo adopters. | Low | High | Keep missing mode -> `single_repo` and make local config optional in that mode. |

---

## Code Samples

Any schema examples in the implementation documentation should be illustrative
and use placeholder repository names, paths, and secret references only. Do not
include production-ready resolver code in documentation.

---

## Implementation Order

1. Confirm #874 has merged into `develop-workflow-hub-mode`.
2. Add `.ai-dev-workflow.local.yaml` to `.gitignore`.
3. Add `.ai-dev-workflow.local.example.yaml` with placeholder local-only
   examples.
4. Add the repository-context resolver and validation command under
   `scripts/development-workflow/`.
5. Add `workflow-lib.sh` wrappers around the resolver.
6. Add fixture-driven resolver tests.
7. Update existing workflow test or CI entry points so the new tests run.
8. Extend repository mode/configuration documentation and `.ai-dev-workflow.yaml`
   comments.
9. Add the `CHANGELOG.md` entry.
10. Run the smoke test runbook and automated validation commands listed in
    **Testing Strategy**.
11. Open a draft implementation PR targeting `develop-workflow-hub-mode`, run
    internal review, the automated reviewer loop, and CI, then mark the PR ready
    for human review.
