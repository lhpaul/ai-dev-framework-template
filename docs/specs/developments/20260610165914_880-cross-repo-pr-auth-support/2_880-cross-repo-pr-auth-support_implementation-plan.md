# Cross-Repository Pull Request Authentication and Operation Support - Implementation Plan

**Spec**: [1_880-cross-repo-pr-auth-support_specs.md](1_880-cross-repo-pr-auth-support_specs.md)
**Smoke test runbook**: [880-cross-repo-pr-auth-support.smoke-test.md](../../../testing/workflow/880-cross-repo-pr-auth-support.smoke-test.md)

---

## Summary

**Approach**: Add a small workflow-hub authentication layer for selected product
repositories, then route product pull-request creation through a helper that
uses the selected product repository slug and an explicit non-logging token
path. Keep shared repository configuration secret-free, keep local secret
references in `.ai-dev-workflow.local.yaml`, and use dry-run fixture coverage to
prove command construction without real credentials.

**Estimated complexity**: M

**Rationale**: The change is security-sensitive but intentionally narrow. It
adds command contracts around token acquisition and PR creation without changing
tracker ownership, reviewer behavior, or product code. The highest risks are
secret disclosure in stdout/stderr, accidentally opening PRs in the workflow hub,
and silently falling back to a human `gh` token when product-repo GitHub App auth
is incomplete.

**Dependencies**: #875 must be merged into `develop-workflow-hub-mode` because
this work depends on shared/local workflow config resolution. #878 should be
available before implementation PR routing is wired into orchestrator-owned
flows; this feature can still land as standalone helpers and docs first.

---

## Verification Log

| Check | Command / query | Result |
| --- | --- | --- |
| Repo revision | `git rev-parse --short HEAD` | `8b30a37` |
| Approved spec | `sed -n '1,360p' docs/specs/developments/20260610165914_880-cross-repo-pr-auth-support/1_880-cross-repo-pr-auth-support_specs.md` | Spec requires GitHub App setup docs, local-only secret refs, token helper behavior, product-repo PR targeting, dry-run validation, and clear auth failures. |
| Local config example | `sed -n '1,220p' .ai-dev-workflow.local.example.yaml` | Placeholder-only local config already includes product repo entries with `private_key_path` and `secret_ref`. |
| Local ignore rule | `sed -n '1,80p' .gitignore` | `.ai-dev-workflow.local.yaml` is already gitignored; no token cache exists today. |
| Repository mode docs | `sed -n '1,260p' docs/workflow/development-workflow/repository-modes.md` | Shared config is versioned and local config is gitignored; product repository identity is selected by name. |
| Config resolver | `rg -n "private_key_path|secret_ref|TARGET_GITHUB_REPO|TARGET_GIT_URL|workflow_hub" scripts/development-workflow/workflow-config-resolver.py scripts/development-workflow/tests/test-workflow-config-resolver.sh` | Resolver rejects local-only keys in shared product repo config and returns product repo context for selected hub targets. |
| Existing GitHub tracker docs | `sed -n '1,180p' docs/workflow/development-workflow/integrations/github-projects.md` | Tracker docs are separate from product-repo PR auth and should remain hub-owned. |

---

## Layer-by-Layer Changes

### Backend / Scripts

- [ ] Extend `workflow-config-resolver.py` to expose auth metadata for a
      selected product repository.
      - Add an auth-focused subcommand or output mode that resolves only field
        presence and local references, not secret values.
      - Support non-secret `github_app.app_id` and
        `github_app.installation_id` under shared
        `workflow_hub.product_repos[]`, with local overrides allowed when an
        operator needs machine-specific values.
      - Support local-only `product_repos[].github_app.private_key_path` and
        `product_repos[].github_app.secret_ref` in
        `.ai-dev-workflow.local.yaml`.
      - Preserve the existing `private_key_path` and `secret_ref` aliases in
        the local example for compatibility, but document the nested
        `github_app` form as preferred for new setup.
      - Keep `LOCAL_ONLY_KEYS` enforcement for shared
        `.ai-dev-workflow.yaml`; add coverage proving secret-bearing auth keys
        cannot be committed under `workflow_hub.product_repos[]`.
      - Do not print private key paths in normal command output unless the user
        explicitly requests local config validation details.
- [ ] Add `scripts/development-workflow/github-app-token.sh`.
      - Accept `--repo <product-name>`, `--repo-root <path>`, `--dry-run`,
        `--status`, and a machine-readable token mode such as `--print-token`.
      - Resolve the selected product repo through the shared/local workflow
        config helpers.
      - Validate required local auth fields before attempting any GitHub call.
      - Generate a GitHub App JWT from the local private key source, exchange it
        for an installation token, and write the token only to stdout in
        explicit machine mode.
      - Send all human logs to stderr and redact token-like and key-like
        material.
      - Fail with distinct messages for missing app id, missing private key or
        secret reference, missing installation access, and permission denied
        where GitHub returns enough detail.
      - Do not fall back to ambient `gh auth token` when the selected GitHub App
        auth source is incomplete.
- [ ] Add `scripts/development-workflow/open-product-pr.sh`.
      - Accept `--repo <product-name>`, `--repo-root <path>`, `--base <branch>`,
        `--head <branch>`, `--title <title>`, `--body-file <path>`, and
        `--dry-run`.
      - Resolve `TARGET_GITHUB_REPO` from `github_repo`, or derive it from
        recognized GitHub `git_url` forms; fail clearly for non-GitHub URLs.
      - In dry-run mode, print target repository, base, head, title, and the
        redacted `gh pr create --repo <owner/repo>` command shape without
        requiring credentials.
      - In live mode, call the token helper, pass the token to `gh` through
        `GH_TOKEN` for that invocation, and never echo the token.
      - Fail before PR creation when product repo selection is missing,
        ambiguous, non-GitHub, or missing local auth configuration.
      - Return a success URL and stable key/value output on successful PR
        creation.
- [ ] Decide explicitly whether a token cache is needed.
      - Default MVP: no persistent token cache.
      - If implementation adds caching, use a local path such as
        `.ai-dev-workflow.auth-cache/`, add it to `.gitignore`, document its
        lifecycle, and test that it is not emitted in shared config examples.
- [ ] Keep tracker and single-repository behavior unchanged.
      - Do not route GitHub Projects reads or updates through the product repo
        token helper.
      - Keep `single_repo` mode on existing `gh` auth behavior.
      - Require explicit workflow-hub product selection for product PR
        operations when multiple product repos exist.

### Tests

- [ ] Add
      `scripts/development-workflow/tests/test-workflow-hub-pr-auth.sh`.
- [ ] Use temporary fixture directories and stubbed `gh`, token exchange, and
      private-key reader commands. Tests must not need live GitHub credentials.
- [ ] Cover:
      - shared `.ai-dev-workflow.yaml` rejects local-only secret-bearing auth
        fields
      - shared `.ai-dev-workflow.yaml` may contain non-secret app id and
        installation id values
      - local `.ai-dev-workflow.local.yaml` accepts placeholder auth refs
      - missing app id reports `missing_app_id`
      - missing private key path or secret ref reports `missing_private_key`
      - missing installation reports `missing_installation`
      - permission failure reports `permission_denied`
      - token helper normal logs do not contain token-like output
      - token helper explicit machine mode prints only the token on stdout
      - product PR dry-run works before real credentials are configured
      - product PR dry-run produces distinct `--repo` values for two product
        repositories
      - live PR helper passes `GH_TOKEN` only to the child `gh pr create`
        command
      - non-GitHub `git_url` fails clearly before auth
      - ambiguous workflow-hub product selection fails before auth or PR
        creation
      - `single_repo` mode behavior is unchanged
- [ ] Add a redaction assertion that scans captured stdout/stderr for fixture
      tokens, private key text, and secret-ref placeholder values.

### Documentation

- [ ] Add
      `docs/workflow/development-workflow/integrations/workflow-hub-github-app.md`.
      - List required GitHub App permissions for product PR creation:
        repository contents read/write as needed for branches, pull requests
        read/write, metadata read, and checks/status read if the helper later
        validates readiness.
      - Document product repository installation steps and where to find app id
        and installation id.
      - Document local-only config fields and safe placeholder examples.
      - Explain that secret manager references are supported as references, not
        secret values, and that the workflow does not require one specific
        secret manager.
      - Explain that no token values, private key contents, or machine-local
        secret locations belong in `.ai-dev-workflow.yaml`.
      - Include dry-run examples for two product repositories.
- [ ] Update
      `docs/workflow/development-workflow/repository-modes.md`.
      - Add a short cross-reference from local workflow configuration to the
        GitHub App auth integration doc.
      - Clarify that product PR helpers target the selected product repository,
        not the hub remote.
- [ ] Update `.ai-dev-workflow.local.example.yaml`.
      - Keep placeholder-only values.
      - Prefer nested `github_app` fields while retaining a compatibility note
        for top-level `private_key_path` / `secret_ref`.
- [ ] Update `docs/workflow/development-workflow/README.md` if the helper
      command becomes part of the normal workflow-hub implementation path.
- [ ] Add the implementation changelog entry under `[Unreleased]` / `### Added`:
      `- **Workflow hub product repository PR authentication** (#880): adds local-only GitHub App auth guidance and helpers for opening product repository pull requests without exposing secrets.`

### Database / Frontend / Infrastructure

- [ ] None. This feature changes local workflow scripts, fixture tests, docs,
      and examples only. CI must not require live GitHub App secrets.

---

## Testing Strategy

**Test types**: Shell fixture tests, resolver regression tests, command-contract
tests, redaction tests, dry-run tests, markdown lint, and shellcheck.

**Key scenarios to test**:

1. Shared config rejects private key paths, secret refs, token values, and local
   auth cache paths (AC2, AC3, AC4).
2. Shared config can hold non-secret app ids and installation ids, while local
   config accepts private key paths and secret refs without printing secret
   values (AC2, AC3).
3. Token helper reports missing app id, missing private key or secret ref,
   missing installation, and permission denied as distinct actionable failures
   (AC8).
4. Token helper never prints token values in normal logs or failure output
   (AC5, AC10).
5. Explicit machine token mode has a narrow stdout contract and keeps human logs
   on stderr (AC5, AC10).
6. PR helper dry-run works without credentials and reports target repository,
   base branch, head branch, title, and redacted command shape (AC6, AC7, AC9).
7. Two product-repo fixtures produce two different `gh pr create --repo`
   targets (AC6, AC7).
8. Live PR helper uses the selected product token only for the child `gh`
   invocation and does not expose it in parent logs (AC10).
9. Missing or ambiguous product repository selection fails before auth or PR
   creation (AC6, AC8).
10. `single_repo` mode remains compatible with existing behavior (AC9).

**Smoke test runbook**:
`docs/testing/workflow/880-cross-repo-pr-auth-support.smoke-test.md`

**Regression suite**:

- `bash scripts/development-workflow/tests/test-workflow-hub-pr-auth.sh`
- `bash scripts/development-workflow/tests/test-workflow-config-resolver.sh`
- `python3 -m py_compile scripts/development-workflow/workflow-config-resolver.py`
- `shellcheck --severity=warning scripts/development-workflow/*.sh scripts/development-workflow/tests/*.sh`
- `npx markdownlint-cli2 "docs/specs/developments/20260610165914_880-cross-repo-pr-auth-support/*.md" "docs/testing/workflow/880-cross-repo-pr-auth-support.smoke-test.md" "CHANGELOG.md"`
- `python3 scripts/lint/markdown-heuristic-lint.py docs/testing/workflow/880-cross-repo-pr-auth-support.smoke-test.md CHANGELOG.md`
- `bash scripts/lint/check-changelog-duplicate-headers.sh CHANGELOG.md`

### Parser-risk Addendum

- **Edge-case enumeration**:
  - no mode declaration
  - explicit `single_repo`
  - `workflow_hub` with one product repo
  - `workflow_hub` with two product repos and no selection
  - unknown product repo selection
  - product repo with `github_repo`
  - product repo with GitHub HTTPS `git_url`
  - product repo with GitHub SSH `git_url`
  - product repo with non-GitHub `git_url`
  - local secret-bearing auth fields missing entirely
  - missing app id
  - missing installation id
  - private key path configured but unreadable
  - secret ref configured but resolver command unavailable
  - both private key path and secret ref configured
  - token exchange returns not found
  - token exchange returns permission denied
  - token exchange returns malformed JSON
  - `gh pr create` fails after token acquisition
  - `--dry-run` with no credentials
  - `--body-file` missing
  - title, base, or head containing shell-sensitive characters
  - fixture token present in child environment but absent from logs
  - future auth cache path configured
- **Unit test mapping**: Add one named assertion for each edge case in
  `scripts/development-workflow/tests/test-workflow-hub-pr-auth.sh`.
- **Suppression semantics**: No new suppression directive format is introduced.
  Any ShellCheck suppression must follow the existing line-level directive with
  inline rationale required by `docs/best-practices/1-general.md`.

---

## Seed Data

No persistent seed data is required. Tests should create temporary workflow hub
fixtures with two product repositories, local config placeholders, stubbed token
exchange responses, and a stubbed `gh` executable that records command
arguments and environment without contacting GitHub.

---

## Documentation Updates

- [ ] `docs/workflow/development-workflow/integrations/workflow-hub-github-app.md`
      - new GitHub App setup and local auth guidance.
- [ ] `docs/workflow/development-workflow/repository-modes.md` - link local
      auth setup to product repository PR ownership.
- [ ] `.ai-dev-workflow.local.example.yaml` - placeholder-only local GitHub App
      auth fields.
- [ ] `docs/workflow/development-workflow/README.md` - only if the PR helper is
      part of the operator-facing workflow command list.
- [ ] `CHANGELOG.md` - add the implementation entry listed in the Documentation
      layer above.
