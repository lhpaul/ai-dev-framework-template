# Repository Modes

This note defines the repository ownership model for the AI development workflow.
It is the source of truth for later workflow-hub implementation work, but this
document by itself does not change runtime behavior, scripts, PR routing, or
configuration requirements.

## Supported Modes

| Code value | Display label | Description |
| --- | --- | --- |
| `single_repo` | Single repository | One repository owns tracker work, specs, plans, implementation branches, PRs, CI, reviewer-loop checks, and releases. |
| `workflow_hub` | Workflow hub | A coordination repository owns portfolio planning and workflow artifacts for one or more product repositories. |
| `product_repo` | Product repository | A product repository receives routed implementation work from a workflow hub and owns product code validation. |

When a repository has no mode declaration, the workflow interprets it as
`single_repo`. Existing adopters keep the current behavior until they explicitly
choose a different mode and install later workflow-hub automation.

## Artifact Ownership

| Artifact | `single_repo` owner | `workflow_hub` owner | `product_repo` owner |
| --- | --- | --- | --- |
| Backlog or tracker items | Current repository tracker | Hub tracker | Hub tracker references product work; product repo does not own portfolio tracking |
| Specs | Current repository | Hub | Hub, unless a later product-specific convention explicitly copies read-only context |
| Plans | Current repository | Hub | Hub, unless a later product-specific convention explicitly copies read-only context |
| Hub-owned smoke runbooks | Current repository | Hub | Not owned by product repo |
| Product-owned smoke runbooks | Current repository | Hub may reference or coordinate them | Product repo owns product validation runbooks |
| Implementation branches | Current repository | Not owned by hub for product code | Product repo |
| Spec PRs | Current repository | Hub | Hub |
| Plan PRs | Current repository | Hub | Hub |
| Code PRs | Current repository | Product repo selected by the work item | Product repo |
| CI checks | Current repository | Hub for hub-doc/tool PRs; product repo for product code PRs | Product repo |
| Reviewer-loop checks | Current repository | Hub for hub-doc/tool PRs; product repo for product code PRs | Product repo |

In `single_repo` mode, all artifact ownership stays exactly as it works today:
the tracker item, spec, plan, implementation branch, PR, CI, reviewer loop, smoke
runbook, and release evidence are all handled in the same repository.

In `workflow_hub` mode, the hub centralizes coordination artifacts. It owns the
tracker item, spec, implementation plan, cross-repository workflow
documentation, and any smoke runbook that validates hub-owned workflow behavior.
The selected product repository owns implementation branches, code PRs, product
CI checks, product reviewer-loop checks, and product smoke runbooks.

In `product_repo` mode, the repository is a target for product implementation
work routed from a hub. It owns the code change and validation artifacts for that
product, while the hub remains the source of truth for portfolio state, specs,
plans, and cross-product coordination.

## PR Ownership

| PR type | `single_repo` target | `workflow_hub` target | `product_repo` target |
| --- | --- | --- | --- |
| Spec PR | Current repository | Hub repository | Hub repository |
| Plan PR | Current repository | Hub repository | Hub repository |
| Code PR | Current repository | Selected product repository for product work; hub repository for hub-only workflow work | Product repository |

A hub-managed item can still be hub-only. For example, a change to hub
protocols, hub docs, or hub-owned orchestration scripts opens its code PR in the
hub. A product implementation opens its code PR in the target product
repository.

## Base Branch Ownership

Base branch checks must run against the repository that owns the next mutating
artifact:

- Hub-owned spec and plan PRs validate against the hub repository's artifact
  base branch, typically the hub default branch.
- Product implementation PRs validate against the selected product repository's
  implementation base branch, usually the product entry's `default_branch` or a
  run-scoped integration branch such as `develop-<slug>`.
- A `/run-epic --base <branch>` override in `workflow_hub` mode describes the
  product implementation base. It must not be used as a precondition that the
  hub repository itself has a branch with the same name.

## Orchestration Ownership

Workflow orchestration scripts keep planning and tracker state in the hub while
allowing implementation actions to target a selected product repository.

- `discover-workflow-state.sh`, `workflow-next-action.sh`, and
  `workflow-batch-plan.sh` accept `--repo <name>` and report
  `WORKFLOW_MODE`, `ACTION_REPOSITORY_KIND`, and the selected repository
  identity for each implementation action.
- `pr-review-loop.sh` and `pr-ci-loop.sh` can target implementation PRs outside
  the hub by accepting `--repo <owner/repo>` or `--product-repo <name>`.
- `post-merge-cleanup.sh --repo <name> <branch>` cleans implementation branches
  in the selected product checkout in `workflow_hub` mode, then returns tracker
  updates to the hub repository.
- Spec, plan, and tracker operations remain hub-owned. Product repository
  selection must not redirect GitHub Projects reads or status updates unless a
  later workflow contract explicitly changes tracker ownership.

When a workflow hub has more than one product repository, implementation
inspection and mutation fail before touching product state unless the caller
selects one product repository.

## Agent Obligations

Agents and command wrappers must make repository ownership visible before they
act. Missing mode or explicit `single_repo` keeps current behavior: the current
repository owns specs, plans, implementation branches, pull requests, reviews,
smoke tests, and cleanup, and no product repository selector is required.

In `workflow_hub` mode:

- Portfolio and item orchestrators include workflow mode, artifact owner, and
  selected product repository context in implementation handoffs.
- Product-manager and tech-lead agents create specs and plans in the hub unless
  a future workflow contract explicitly says otherwise.
- Developer agents state the selected product repository, local path or remote
  identity, and mutation target before file edits, branch creation, commits, or
  implementation PR creation.
- Spec and plan reviewers report the hub-owned artifact they reviewed; code
  reviewers report the product or hub repository that owns the implementation
  artifact under review.
- Smoke testers report whether the runbook or implementation artifact is
  hub-owned or product-repository-owned.
- Reviewer-loop wrappers remain thin: they pass repository context through to
  shared scripts/helpers and do not implement independent product repository
  selection rules.

If product repository context is missing or ambiguous for mutation-oriented
work, the agent must stop before modifying files, creating branches, committing,
or opening implementation PRs.

## Target Product Repository Selection

A hub-managed work item must identify one visible and unambiguous target product
repository before implementation work is routed to a product repository. The
target value must be reviewable from the work item context, stable enough for
automation to resolve, and clear to humans reading the spec, plan, and PRs.

This note does not prescribe the storage format for the target repository value.
Later implementation items may choose a tracker field, issue-body field, local
configuration mapping, command flag, or another explicit mechanism. Whatever
format is chosen must preserve these rules:

- A missing target is flagged before product implementation routing starts.
- An ambiguous target is flagged before product implementation routing starts.
- Multi-repository implementation work must make every target explicit instead
  of relying on an implicit default.
- Hub-only workflow changes must be distinguishable from product-code changes.

## Hub-Owned And Product-Injected Content

The workflow hub owns content that defines or coordinates the development
process:

- Tracker coordination and portfolio status.
- Specs and implementation plans for hub-managed work.
- Cross-repository workflow documentation and operating runbooks.
- Hub-owned workflow protocols, agent wrappers, and orchestration scripts.
- Hub smoke runbooks that validate workflow behavior rather than product
  behavior.

Product repositories own or receive content that must run next to product code:

- Product implementation branches and product code PRs.
- Product CI and reviewer-loop execution for product code changes.
- Product smoke runbooks and regression fixtures.
- Local agent wrappers or thin integration files when later workflow-hub
  injection support provides them.
- Minimal workflow helper files required for local product-repo operation.

Product-injected framework content should be the smallest useful subset. A
product repository should not receive hub-owned tracker artifacts, historical
specs, implementation plans, or cross-product coordination state unless a later
workflow explicitly documents why that copy is required.

The sync-template workflow enforces this boundary through `sync-manifest.yaml`
`mode_scope` metadata:

- `single_repo` selects all manifest entries and preserves the existing
  compatibility file set.
- `workflow_hub` selects `shared` and `hub_only` entries, then reports
  `product_repo_injection` entries as skipped.
- `product_repo` selects `shared` and `product_repo_injection` entries, then
  reports `hub_only` entries as skipped.

Unknown repository roles, missing entry `mode_scope` values, and unknown
`mode_scope` values fail closed before file changes are applied. Dry-run and
apply paths use the same selected manifest entry set so preview output and the
actual apply set cannot diverge.

Inspectable skeletons make this boundary visible without applying it:

- `template/workflow-hub/` lists hub-owned protocols, scripts, agent wrappers,
  project workflow configuration, and workflow runbooks.
- `template/product-repo-injection/` lists minimal product repository
  integration candidates and excludes hub-owned tracker, spec, implementation
  plan, and hub-only runbook artifacts unless a later workflow marks a specific
  artifact as required.

The skeleton manifests reference canonical source paths instead of copying full
framework trees, so they can be reviewed without creating duplicate files that
drift from the template.

## Generic Multi-Product Example

A team can run one hub and multiple product repositories:

```text
workflow-hub
  owns: tracker items, specs, plans, workflow docs, hub orchestration scripts

mobile-app
  owns: mobile product code, mobile implementation PRs, mobile CI, mobile smoke runbooks

admin-portal
  owns: admin product code, admin implementation PRs, admin CI, admin smoke runbooks
```

In this topology, a hub work item for a mobile feature records `mobile-app` as
its target product repository. The spec and plan PRs are opened in
`workflow-hub`; the implementation branch, code PR, CI, reviewer-loop checks,
and product smoke runbook execution happen in `mobile-app`.

A different work item for an admin workflow records `admin-portal` as its target
product repository and follows the same split. A hub-only workflow improvement,
such as updating orchestration protocols, has no product target and opens its
code PR in `workflow-hub`.

## Adoption Guides

Use these guides when moving from the operating model to a concrete setup:

- [Workflow Hub Setup](workflow-hub-setup.md)
- [Product Repository Injection](product-repo-injection.md)
- [Cross-Repository PR Flow](cross-repo-pr-flow.md)

## Shared And Local Workflow Configuration

Repository mode configuration is split across one versioned shared file and one
optional local file:

- `.ai-dev-workflow.yaml` is committed and may contain only repository-safe
  workflow identity, provider selection, and non-secret metadata.
- `.ai-dev-workflow.local.yaml` is gitignored and contains machine-local paths,
  checkout defaults, secret references, and local tool or reviewer overrides.
- `.ai-dev-workflow.local.example.yaml` is committed as a placeholder-only
  starting point for local setup.

Omitting `mode` in `.ai-dev-workflow.yaml` resolves as `single_repo`.

Valid `mode` values are:

- `single_repo`
- `workflow_hub`
- `product_repo`

### Shared Hub Configuration

A `workflow_hub` repository declares stable product repository identity under
`workflow_hub.product_repos[]`:

```yaml
schema_version: 2
mode: workflow_hub

workflow_hub:
  product_repos:
    - name: mobile-app
      github_repo: example/mobile-app
      default_branch: main
      ci_policy: required
      role: mobile
      scope: customer-facing app
      tracker:
        component: mobile
    - name: admin-portal
      git_url: git@github.com:example/admin-portal.git
      default_branch: develop
```

Each product entry needs a stable `name` and either `github_repo` or `git_url`.
Optional shared fields may include `default_branch`, `ci_policy` (`required` or
explicit `none` for repositories without GitHub Actions checks), `role`, `scope`,
`tracker` hints, and non-secret app identifiers. Shared product entries must not contain
local checkout paths, private key paths, secret values, or machine-specific tool
settings.

When a hub has more than one product repository, callers must pass the target
product name explicitly. Ambiguous target selection fails before branch, PR,
checkout, or routing actions run.

### Product Repository Configuration

A `product_repo` declares the hub that owns portfolio workflow state:

```yaml
schema_version: 2
mode: product_repo

product_repo:
  default_branch: main
  workflow_hub:
    github_repo: example/workflow-hub
```

The hub reference must include `github_repo` or `git_url`.

### Local Configuration

Local checkout and secret-reference data belongs in
`.ai-dev-workflow.local.yaml`:

```yaml
checkout_root: ../repos

product_repos:
  - name: mobile-app
    local_path: ../repos/mobile-app
    github_app:
      private_key_path: ~/.config/example/mobile-app-github-app.pem
      secret_ref: op://ExampleVault/mobile-app-github-app/private-key
  - name: admin-portal
    github_app:
      secret_ref: op://ExampleVault/admin-portal-github-app/private-key

review:
  on_draft:
    runner:
      - codex
  internal_reviewers_unavailable_policy: warn
```

For a hub target, local path resolution uses this order:

1. `product_repos[].local_path` or `product_repos[].checkout_path` in
   `.ai-dev-workflow.local.yaml`.
2. `checkout_root` plus the product repository `name`.
3. A clear validation error when the caller requires a local checkout and no
   path can be resolved.

Local config is optional for `single_repo` mode. It is required only when a
workflow hub action needs a local product checkout path that cannot be derived
safely.

Workflow hub operators can inspect and prepare product repositories with:

```bash
scripts/development-workflow/hub-status.sh --repo mobile-app
scripts/development-workflow/hub-status.sh --all
scripts/development-workflow/hub-sync-product-repos.sh --repo mobile-app
scripts/development-workflow/hub-list-prs.sh --all
```

These commands are workflow-hub-only surfaces:

- `hub-status.sh` is read-only and reports local checkout path, current branch,
  clean or dirty state, remote visibility, and a categorized summary.
- `hub-sync-product-repos.sh` refuses dirty, ahead-only, or diverged checkouts;
  it only fast-forwards clean repositories and writes local path entries to
  `.ai-dev-workflow.local.yaml` after explicit bootstrap confirmation.
- `hub-list-prs.sh` is read-only and targets the resolved product repository
  with `gh pr list --repo <owner/repo>`, never the workflow hub repository as a
  fallback.

Workflow-hub product PR authentication uses the same split: shared config may
store non-secret GitHub App IDs and installation IDs, while private key paths
and secret-manager references stay local-only. See
[`integrations/workflow-hub-github-app.md`](integrations/workflow-hub-github-app.md)
for the setup guide and dry-run helper commands.

### Non-Secret Workflow Hub Smoke Fixture

Template maintainers can run a deterministic workflow-hub fixture without
private repositories or credentials:

```bash
bash scripts/development-workflow/tests/test-workflow-hub-smoke-fixtures.sh
```

The committed fixture seed lives under
`scripts/development-workflow/tests/fixtures/workflow-hub-smoke/`. It models one
hub and two placeholder product repositories, `mobile-app` and `admin-portal`,
using `example/*` repository identities. The harness copies the seed into a
temporary directory, writes local-only checkout paths there, creates temporary
git repositories for the products, and validates:

- workflow-hub config parsing and product repository resolution
- local path precedence from `.ai-dev-workflow.local.yaml` and `checkout_root`
- status and sync command behavior for both dummy products
- product branch and PR routing through dry-run commands
- `sync-manifest.yaml` mode-scope classification
- missing-mode and explicit `single_repo` regression behavior

The default path is safe for CI and does not perform live GitHub writes. Live
GitHub App validation is an explicit operator action via `--live-github-app`
against safe test repositories only.

### Compatibility And Precedence

Local workflow configuration belongs in `.ai-dev-workflow.local.yaml`. Runtime
review overrides, checkout paths, and local secret references must use that
local YAML file rather than ad hoc local config files.

Effective precedence is:

1. `.ai-dev-workflow.local.yaml` for local config keys.
2. `.ai-dev-workflow.yaml` shared config.
3. Built-in defaults, including missing `mode` resolving as `single_repo`.

### Validation And Shell Helpers

Validate repository-context configuration with:

```bash
scripts/development-workflow/validate-workflow-config.sh
scripts/development-workflow/validate-workflow-config.sh --repo mobile-app --require-local
```

The underlying resolver is
`scripts/development-workflow/workflow-config-resolver.py`. It uses only the
Python standard library and supports the constrained YAML subset used by the
workflow config files: nested mappings, lists, scalar values, comments, and
two-space indentation. Unsupported or malformed config fails closed with a
file-specific error.

`workflow-lib.sh` exposes shell-callable helpers that print `KEY=value` output:

- `workflow_repository_mode`
- `workflow_repository_context`
- `workflow_validate_repository_context`
- `workflow_review_override_context`

## Non-Goals

This note does not:

- Migrate existing downstream repositories.
- Define a required secret manager or store secret values.

Those behaviors belong to later workflow-hub implementation items. Until those
items land, missing mode remains `single_repo` and existing repositories keep the
current single-repository workflow.

The `sync-manifest.yaml` `mode_scope` metadata is consumed by sync-template
selection. Current readers still preserve single-repository compatibility, but
workflow hubs and product repositories receive role-specific selected and
skipped file sets.
